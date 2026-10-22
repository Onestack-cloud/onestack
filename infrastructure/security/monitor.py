#!/usr/bin/env python3
"""Read-only runtime/image inventory. Reports contain metadata, never environments."""
import argparse
import base64
import datetime as dt
import glob
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import shutil
import sys
import time
import urllib.request
import urllib.error

BASELINE = {'22': '22.23.4', '24': '24.22.1', '26': '26.12.1'}
NODE_FEED = 'https://nodejs.org/dist/index.json'
SCHEDULE = 'https://raw.githubusercontent.com/nodejs/Release/main/schedule.json'
PROBE = r'''const fs=require('fs'); const external=[];
for(const path of ['/usr/lib/node_modules/npm/node_modules/undici/package.json','/usr/local/lib/node_modules/npm/node_modules/undici/package.json',(()=>{try{return require.resolve('undici/package.json')}catch{return ''}})()]){
 if(path&&fs.existsSync(path)){const p=JSON.parse(fs.readFileSync(path));external.push({path,version:p.version})}}
console.log(JSON.stringify({node:process.versions.node,execPath:process.execPath,
alpine:process.platform==='linux'&&!process.report.getReport().header.glibcVersionRuntime,external}));'''


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def fetch(url, data=None):
    req = urllib.request.Request(url, data=json.dumps(data).encode() if data is not None else None,
                                 headers={'User-Agent': 'Onestack-Security/1', 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=40) as response:
        return json.load(response)


def run(args, timeout=30, env=None):
    p = subprocess.run(args, capture_output=True, text=True, timeout=timeout, env=env)
    if p.returncode:
        raise RuntimeError(f'{Path(args[0]).name} failed with exit {p.returncode}')
    return p.stdout


def numeric(value):
    if not re.fullmatch(r'v?\d+\.\d+\.\d+', value):
        raise ValueError('Invalid exact runtime version')
    return tuple(map(int, value.lstrip('v').split('.')))


def floors_for(releases):
    if not isinstance(releases, list) or not releases:
        raise ValueError('Incomplete Node release feed')
    floors = dict(BASELINE)
    for release in releases:
        value = release['version'].lstrip('v')
        major = str(numeric(value)[0])
        if not isinstance(release.get('security'), bool):
            raise ValueError('Missing release security metadata')
        if release['security'] and numeric(value) > numeric(floors.get(major, f'{major}.0.0')):
            floors[major] = value
    return floors


def assess(value, floors, schedule, date):
    major = str(numeric(value)[0])
    dates = schedule.get('v' + major)
    if not dates or not floors.get(major):
        return 'untracked Node release line'
    if date < dates['start'] or date >= dates['end']:
        return 'unsupported Node release line'
    if numeric(value) < numeric(floors[major]):
        return 'requires Node ' + floors[major] + ' or later in this major'
    return None


def atomic(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value, indent=2) + '\n')
    os.chmod(temp, 0o600)
    temp.replace(path)


def host_inventory(config):
    records, errors, processes = [], [], []
    paths = set()
    for pattern in config.get('runtimeGlobs', []):
        paths.update(glob.glob(os.path.expanduser(pattern), recursive=True))
    if config.get('inspectProcesses') and sys.platform.startswith('linux'):
        for entry in Path('/proc').glob('[0-9]*/exe'):
            try:
                target = os.readlink(entry)
                cgroup = entry.with_name('cgroup').read_text()
                if 'docker' in cgroup or 'containerd' in cgroup:
                    continue
                if Path(target.removesuffix(' (deleted)')).name == 'node':
                    paths.add(str(entry))
            except (FileNotFoundError, PermissionError, ProcessLookupError):
                pass
    if config.get('inspectProcesses') and sys.platform == 'darwin':
        for line in run(['ps', '-axo', 'pid=,comm=']).splitlines():
            parts = line.strip().split(None, 1)
            if len(parts) != 2 or Path(parts[1]).name != 'node':
                continue
            pid, executable = parts
            try:
                mapped = run(['lsof', '-a', '-p', pid, '-d', 'txt', '-Fin'], 10)
                inode = None
                for field in mapped.splitlines():
                    if field.startswith('i'):
                        inode = int(field[1:])
                    elif field.startswith('n') and Path(field[1:].removesuffix(' (deleted)')).name == 'node':
                        path = field[1:].removesuffix(' (deleted)')
                        paths.add(path)
                        installed = Path(path)
                        processes.append({'pid': int(pid), 'path': path,
                                          'requiresRestart': not installed.is_file() or inode != installed.stat().st_ino})
                        break
                else:
                    if subprocess.run(['ps', '-p', pid, '-o', 'comm='], capture_output=True, text=True).stdout.strip():
                        errors.append('loaded executable could not be verified: ' + pid)
            except Exception:
                if subprocess.run(['ps', '-p', pid, '-o', 'comm='], capture_output=True, text=True).stdout.strip():
                    errors.append('process mapping unavailable: ' + pid)
    env = dict(os.environ)
    env.pop('NODE_OPTIONS', None)
    for path in sorted(paths):
        if not Path(path).is_file():
            continue
        try:
            record = json.loads(run([path, '-e', PROBE], 15, env))
            records.append({'target': 'host:' + path, **record})
        except Exception:
            errors.append('runtime probe failed: ' + path)
    if config.get('requireHostNode') and not records:
        errors.append('no host Node runtime was observed')
    containers = []
    if config.get('docker'):
        docker = config.get('dockerCommand', ['docker'])
        containers = [json.loads(line) for line in run(docker + ['ps', '--no-trunc', '--format', '{{json .}}']).splitlines()]
        for item in containers:
            target = item['Names']
            observed = False
            for executable in ['node'] + config.get('containerNodePaths', []):
                p = subprocess.run(docker + ['exec', '-e', 'NODE_OPTIONS=', target, executable, '-e', PROBE],
                                   capture_output=True, text=True, timeout=20)
                if not p.returncode:
                    try:
                        records.append({'target': 'docker:' + target + ':' + executable, **json.loads(p.stdout)})
                        observed = True
                    except ValueError:
                        errors.append('invalid container runtime probe: ' + target)
            if not observed and target in config.get('requireNodeContainers', []):
                errors.append('required container runtime unavailable: ' + target)
        running = {x['Names'] for x in containers}
        if 'knownContainers' in config:
            for name in running - set(config['knownContainers']):
                if not any(name.startswith(prefix) for prefix in config.get('knownContainerPrefixes', [])):
                    errors.append('unregistered active container: ' + name)
        for missing in set(config.get('requireNodeContainers', [])) - running:
            errors.append('required Node container missing: ' + missing)
        for name, expected in config.get('expectedImageDigests', {}).items():
            if name in running:
                actual = run(docker + ['inspect', '--format', '{{.Image}}', name]).strip()
                if actual != expected:
                    errors.append('unverified image change: ' + name)
    reports = {}
    if config.get('requireScanReports'):
        for mode in ['images', 'os']:
            try:
                report = json.loads((Path('/var/lib/onestack-security') / (mode + '.json')).read_text())
                reports[mode] = {key: report.get(key) for key in ['checkedAt', 'state']}
                reports[mode]['findings'] = len(report.get('findings', []))
            except (OSError, ValueError):
                reports[mode] = {'state': 'unknown', 'checkedAt': None}
    return {'runtimes': records, 'errors': errors, 'processes': processes, 'reports': reports,
            'containers': [{'name': x['Names'], 'image': x['Image']} for x in containers]}


def guest_inventory(name, config):
    source = Path(__file__).read_bytes()
    code = ('import base64; ns={"__name__":"security_probe"}; exec(compile(base64.b64decode(' +
            repr(base64.b64encode(source).decode()) + '),"<security-probe>","exec"),ns); '
            'print(ns["json"].dumps(ns["host_inventory"](' + repr(config) + ')))')
    packet = {'execute': 'guest-exec', 'arguments': {'path': '/usr/bin/python3', 'arg': ['-c', code], 'capture-output': True}}
    pid = json.loads(run(['virsh', 'qemu-agent-command', name, json.dumps(packet)]))['return']['pid']
    until = time.monotonic() + 180
    while time.monotonic() < until:
        packet = {'execute': 'guest-exec-status', 'arguments': {'pid': pid}}
        result = json.loads(run(['virsh', 'qemu-agent-command', name, json.dumps(packet)]))['return']
        if result.get('exited'):
            if result.get('exitcode'):
                raise RuntimeError('Guest inventory failed')
            return json.loads(base64.b64decode(result['out-data']))
        time.sleep(1)
    raise TimeoutError('Guest inventory remains incomplete')


def runtime_scan(config):
    report = {'checkedAt': now(), 'state': 'unknown', 'runtimes': [], 'errors': [], 'findings': []}
    floors = floors_for(fetch(NODE_FEED))
    schedule = fetch(SCHEDULE)
    report['floors'] = floors
    inventory = host_inventory(config)
    report['containers'] = inventory['containers']
    report['runtimes'] = inventory['runtimes']
    report['processes'] = inventory['processes']
    report['errors'] += inventory['errors']
    guests = config.get('guests', {})
    running_guests = {x for x in run(['virsh', 'list', '--name']).splitlines() if x} if guests else set()
    report['inactiveGuests'] = sorted(set(guests) - running_guests)
    for name in running_guests - set(guests):
        report['errors'].append('unregistered active guest: ' + name)
    for name, guest in guests.items():
        if name not in running_guests:
            continue
        try:
            result = guest_inventory(name, guest)
            report['runtimes'] += [{**x, 'target': name + ':' + x['target']} for x in result['runtimes']]
            report['errors'] += [name + ': ' + x for x in result['errors']]
            for mode, receipt in result.get('reports', {}).items():
                if receipt['state'] == 'affected':
                    report['findings'].append({'target': name + ':' + mode, 'detail': 'guest scan has high/critical findings', 'count': receipt['findings']})
                elif receipt['state'] != 'checked':
                    report['errors'].append('guest scan unavailable: ' + name + ':' + mode)
                if not receipt.get('checkedAt') or time.time() - dt.datetime.fromisoformat(receipt['checkedAt']).timestamp() > 115200:
                    report['errors'].append('guest scan is stale: ' + name + ':' + mode)
        except Exception:
            report['errors'].append('guest inventory unavailable: ' + name)
    for item in report['runtimes']:
        detail = assess(item['node'], floors, schedule, report['checkedAt'][:10])
        if detail:
            report['findings'].append({'target': item['target'], 'version': item['node'], 'detail': detail})
    for item in report['processes']:
        if item['requiresRestart']:
            report['findings'].append({'target': str(item['pid']), 'detail': 'loaded Node executable differs from its installed file; restart required'})
    versions = sorted({x['version'] for item in report['runtimes'] for x in item.get('external', [])})
    if versions:
        advisory = fetch('https://api.osv.dev/v1/querybatch', {'queries': [
            {'package': {'name': 'undici', 'ecosystem': 'npm'}, 'version': value} for value in versions]})
        if len(advisory.get('results', [])) != len(versions):
            raise ValueError('Incomplete Undici advisory results')
        for value, result in zip(versions, advisory['results']):
            if result.get('vulns'):
                report['findings'].append({'package': 'undici', 'version': value,
                                           'targets': [item['target'] for item in report['runtimes']
                                                       if any(x['version'] == value for x in item.get('external', []))],
                                           'advisories': [x['id'] for x in result['vulns']]})
    report['state'] = 'unknown' if report['errors'] else 'affected' if report['findings'] else 'checked'
    return report


def image_scan(config, output):
    report = {'checkedAt': now(), 'state': 'unknown', 'images': [], 'errors': [], 'findings': []}
    docker = config.get('dockerCommand', ['docker'])
    images = sorted(set(run(docker + ['ps', '--no-trunc', '--format', '{{.Image}}']).splitlines() + config.get('extraImages', [])))
    cache = output / 'image-cache'
    cache.mkdir(parents=True, exist_ok=True)
    update_database(config, output)
    db = json.loads(run([config['grype'], 'db', 'status', '-o', 'json']))
    if db.get('valid') is not True or (not db.get('built') and not db.get('builtAt')):
        raise ValueError('Scanner database age unavailable')
    report['database'] = db
    seen = set()
    for image in images:
        try:
            digest = json.loads(run(docker + ['image', 'inspect', image, '--format', '{{json .Id}}']))
            if digest in seen:
                continue
            seen.add(digest)
            identifier = hashlib.sha256(digest.encode()).hexdigest()[:24]
            target = cache / (identifier + '.json')
            with target.open('w') as stream:
                environment = dict(os.environ)
                if config.get('dockerSocket'):
                    environment['DOCKER_HOST'] = config['dockerSocket']
                p = subprocess.run([config['grype'], 'docker:' + digest, '-o', 'json'], stdout=stream, env=environment,
                                   stderr=subprocess.DEVNULL, timeout=1200)
            if p.returncode:
                raise RuntimeError('Image scan failed')
            raw = json.loads(target.read_text())
            severe = [{'id': x['vulnerability']['id'], 'severity': x['vulnerability']['severity'],
                       'package': x['artifact']['name'], 'version': x['artifact']['version'],
                       'fix': x['vulnerability'].get('fix', {})}
                      for x in raw['matches'] if x['vulnerability']['severity'].lower() in ['high', 'critical']]
            report['images'].append({'image': image, 'digest': digest, 'highCritical': len(severe)})
            report['findings'] += [{**x, 'image': image} for x in severe]
        except Exception:
            report['errors'].append('image scan incomplete: ' + image)
    if not images:
        report['errors'].append('No running images were observed')
    report['state'] = 'unknown' if report['errors'] else 'affected' if report['findings'] else 'checked'
    return report


def availability_scan(config):
    report = {'checkedAt': now(), 'state': 'checked', 'checks': [], 'findings': []}
    for check in config.get('publicChecks', []):
        try:
            request = urllib.request.Request(check['url'], headers={'User-Agent': 'Onestack-Security/1'})
            with urllib.request.urlopen(request, timeout=20) as response:
                passed = response.status == check['expected']
                result = {'url': check['url'], 'status': response.status, 'passed': passed}
        except urllib.error.HTTPError as error:
            result = {'url':check['url'], 'status':error.code, 'passed':error.code == check['expected']}
        except Exception:
            result = {'url': check['url'], 'passed': False}
        report['checks'].append(result)
        if not result['passed']:
            report['findings'].append(result)
    for domain, expected in config.get('nameservers', {}).items():
        try:
            raw = fetch('https://dns.google/resolve?name=' + domain + '&type=NS')
            actual = sorted(x['data'].rstrip('.').lower() for x in raw.get('Answer', []) if x['type'] == 2)
            result = {'domain': domain, 'nameservers': actual, 'passed': raw['Status'] == 0 and actual == sorted(expected)}
        except Exception:
            result = {'domain': domain, 'passed': False, 'state': 'unknown'}
        report['checks'].append(result)
        if not result['passed']:
            report['findings'].append(result)
    report['state'] = 'affected' if report['findings'] else 'checked'
    return report


def os_scan(config, output):
    sbom = output / 'os.sbom.json'
    root = output / 'os-package-metadata'
    for source in ['/var/lib/dpkg/status', '/etc/os-release']:
        target = root / source.lstrip('/')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    command = [config['syft'], 'scan', 'dir:' + str(root), '--override-default-catalogers', 'dpkg-db-cataloger',
               '--parallelism', '1', '-o', 'syft-json=' + str(sbom)]
    run(command, 600)
    inventory = json.loads(sbom.read_text())
    if len(inventory.get('artifacts', [])) < 20 or not inventory.get('distro'):
        raise ValueError('OS package inventory is incomplete')
    update_database(config, output)
    raw = json.loads(run([config['grype'], 'sbom:' + str(sbom), '-o', 'json'], 600))
    findings = [{'id': x['vulnerability']['id'], 'severity': x['vulnerability']['severity'],
                 'package': x['artifact']['name'], 'version': x['artifact']['version'],
                 'fix': x['vulnerability'].get('fix', {})}
                for x in raw['matches'] if x['vulnerability']['severity'].lower() in ['high', 'critical']]
    return {'checkedAt': now(), 'state': 'affected' if findings else 'checked',
            'packages': len(inventory['artifacts']), 'findings': findings}


def update_database(config, output):
    # OS and image timers share one cache. Serialise imports so a cold start
    # cannot unpack two multi-gigabyte databases at once.
    with (output / 'database.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        run([config['grype'], 'db', 'update'], 2400)


def health(output, requirements, timestamp=None):
    timestamp = time.time() if timestamp is None else timestamp
    issues = []
    for filename, max_age in requirements.items():
        try:
            report = json.loads((output / filename).read_text())
            checked = dt.datetime.fromisoformat(report['checkedAt']).timestamp()
            if checked > timestamp + 300 or timestamp - checked > max_age:
                issues.append(filename + ': stale or invalid timestamp')
            if report['state'] != 'checked':
                issues.append(filename + ': ' + report['state'])
        except (OSError, ValueError, KeyError, TypeError):
            issues.append(filename + ': missing or invalid')
    return {'checkedAt': now(), 'state': 'attention' if issues else 'checked', 'issues': issues}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['runtime', 'images', 'os', 'availability', 'health'])
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text())
    output = Path(args.output)
    try:
        if args.mode == 'runtime':
            report = runtime_scan(config)
        elif args.mode == 'images':
            report = image_scan(config, output)
        elif args.mode == 'availability':
            report = availability_scan(config)
        elif args.mode == 'os':
            report = os_scan(config, output)
        else:
            report = health(output, config['requiredReports'])
    except Exception as error:
        report = {'checkedAt': now(), 'state': 'unknown', 'errorType': type(error).__name__}
        if isinstance(error, (RuntimeError, ValueError)):
            report['detail'] = str(error)[:250]
    atomic(output / (args.mode + '.json'), report)
    print(json.dumps({'state': report['state'], 'mode': args.mode, 'findings': len(report.get('findings', [])),
                      'errors': len(report.get('errors', [])), 'report': str(output / (args.mode + '.json'))}))
    return 0 if report['state'] == 'checked' else 1


if __name__ == '__main__':
    sys.exit(main())
