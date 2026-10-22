#!/usr/bin/env python3
"""Use existing local CLI credentials in memory; never export them to another host."""
import argparse
import datetime as dt
import json
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import fcntl
from runtime_updater import maintain
import providers
from monitor import atomic, now
import importlib.util

spec = importlib.util.spec_from_file_location('prepare_pins', Path(__file__).with_name('prepare-pins.py'))
pin_preparation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pin_preparation)
spec = importlib.util.spec_from_file_location('source_monitor', Path(__file__).with_name('source-monitor.py'))
source_monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source_monitor)
from monitor import fetch, floors_for, assess, NODE_FEED, SCHEDULE


def preflight(config, state):
    directory = Path(config['renovate']).parents[3]
    report = {'state': 'unknown'}
    node = subprocess.run([config['node'], '--version'], capture_output=True, text=True, timeout=15)
    if node.returncode:
        raise RuntimeError('Maintenance Node unavailable')
    value = node.stdout.strip().lstrip('v')
    floors = floors_for(fetch(NODE_FEED))
    if assess(value, floors, fetch(SCHEDULE), dt.datetime.now(dt.timezone.utc).date().isoformat()):
        raise RuntimeError('Maintenance Node needs a supported security update')
    audit = subprocess.run([config['bun'], 'audit', '--json', '--audit-level=high'], cwd=directory,
                           capture_output=True, text=True, timeout=120)
    if audit.returncode not in [0, 1]:
        raise RuntimeError('Maintenance tooling audit unavailable')
    findings = json.loads(audit.stdout)
    if not isinstance(findings, dict) or findings.get('error') or findings.get('errors'):
        raise RuntimeError('Maintenance tooling advisory coverage incomplete')
    severe = []
    for name, entries in findings.items():
        if not isinstance(entries, list):
            raise RuntimeError('Invalid maintenance tooling advisory result')
        for entry in entries:
            if entry.get('severity') in ['high', 'critical']:
                severe.append({'package': name, 'url': entry.get('url')})
    allowed = {'package': 'braces', 'url': 'https://github.com/advisories/GHSA-vfj7-8cjw-p6xm'}
    if any(item != allowed for item in severe):
        raise RuntimeError('New unmitigated maintenance tooling vulnerability')
    manifest = json.loads((directory / 'backport.json').read_text())
    backport = manifest['patch']
    if dt.datetime.now(dt.timezone.utc).isoformat() >= backport['reviewBefore']:
        raise RuntimeError('Maintenance security backport review overdue')
    patch = directory / 'patches' / Path(backport['patch']).name
    if hashlib.sha256(patch.read_bytes()).hexdigest() != backport['sha256']:
        raise RuntimeError('Maintenance security patch changed')
    verify = subprocess.run([config['node'], str(directory / 'verify-braces.mjs')],
                            capture_output=True, text=True, timeout=30)
    if verify.returncode:
        raise RuntimeError('Maintenance security backport failed verification')
    report = {'state': 'checked', 'node': value, 'upstreamFindings': severe,
              'verifiedMitigations': [allowed] if severe else []}
    (state / 'tooling.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


def credential(profile, env):
    if profile == 'gitlab':
        command = ['glab', 'config', 'get', 'token', '--host', 'gitlab.com']
    else:
        if profile == 'wcs':
            env['GH_CONFIG_DIR'] = str(Path.home() / '.config/gh-wcs')
        command = ['gh', 'auth', 'token']
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=30)
    token = result.stdout.strip()
    if result.returncode or len(token) < 20 or '\n' in token:
        raise RuntimeError('Existing platform credential unavailable')
    return token


def execute(config, state, dry_run=False):
    state.mkdir(parents=True, exist_ok=True)
    os.chmod(state, 0o700)
    try:
        tooling = preflight(config, state)
    except Exception as error:
        report = {'checkedAt': dt.datetime.now(dt.timezone.utc).isoformat(), 'state': 'unknown',
                  'phase': 'tooling preflight before credentials', 'errorType': type(error).__name__}
        (state / 'status.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report))
        return 1
    try:
        wrangler = Path(config['renovate']).parents[3] / 'node_modules/wrangler/bin/wrangler.js'
        session = subprocess.run([config['node'], str(wrangler), 'whoami'], capture_output=True, timeout=90)
        if session.returncode:
            raise RuntimeError('Supported Cloudflare session refresh failed')
        provider_report = providers.scan(state, config.get('cloudflareBuildsCredentialRefs'))
    except Exception as error:
        provider_report = {'checkedAt':now(), 'state':'unknown', 'errorType':type(error).__name__}
        atomic(state / 'providers.json', provider_report)
    source_report = source_monitor.scan(config['repositories'], state)
    rows = []
    for profile in ['github', 'wcs', 'gitlab']:
        env = {key: value for key, value in os.environ.items() if key in ['HOME', 'PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'SSH_AUTH_SOCK']}
        env['PATH'] = config['toolPath'] + ':' + env.get('PATH', '')
        group = [x for x in config['repositories'] if x['profile'] == profile]
        settings = {'platform': 'gitlab' if profile == 'gitlab' else 'github',
                    'repositories': [x['repository'] for x in group], 'autodiscover': False,
                    'onboarding': False, 'requireConfig': 'required', 'binarySource': 'global',
                    'allowScripts': False, 'allowPlugins': False, 'allowedCommands': [],
                    'allowedUnsafeExecutions': [], 'exposeAllEnv': False, 'internalHostAccess': 'block',
                    'baseDir': str(state / profile), 'cacheDir': str(state / (profile + '-cache')),
                    'gitAuthor': 'Security maintenance <security-maintenance@users.noreply.github.com>'}
        if dry_run:
            settings['dryRun'] = 'full'
        try:
            env['RENOVATE_TOKEN'] = credential(profile, env)
            pin_updates = []
            if not dry_run:
                for repository in group:
                    pin_updates.append(pin_preparation.prepare(repository, profile, env))
            env['LOG_LEVEL'] = 'info'
            env['NODE_OPTIONS'] = '--max-old-space-size=768'
            with tempfile.NamedTemporaryFile(mode='w', suffix='.json', dir=state) as source:
                json.dump(settings, source)
                source.flush()
                env['RENOVATE_CONFIG_FILE'] = source.name
                log_path = state / (profile + '.log')
                with log_path.open('w') as log:
                    os.chmod(log_path, 0o600)
                    result = subprocess.run([config['node'], config['renovate']], env=env,
                                            stdout=log, stderr=subprocess.STDOUT, timeout=1800)
            pending = log_path.read_text(errors='replace').count('"result": "disabled-no-config"')
            rows.append({'profile': profile, 'exit': result.returncode, 'repositories': len(group),
                         'pendingRepositoryConfigs': pending, 'dryRun': dry_run, 'pinnedRuntimeUpdates': pin_updates})
        except Exception as error:
            rows.append({'profile': profile, 'state': 'unknown', 'errorType': type(error).__name__, 'dryRun': dry_run})
    report = {'checkedAt': dt.datetime.now(dt.timezone.utc).isoformat(), 'runs': rows,
              'tooling': tooling,
              'providers': provider_report,
              'sources': source_report,
              'state': 'unknown' if source_report['state']=='unknown' or provider_report['state']=='unknown' or any(x.get('exit', 1) != 0 for x in rows) else 'awaiting repository configuration'
                       if any(x.get('pendingRepositoryConfigs') for x in rows) else 'affected' if source_report['state']=='affected' or provider_report['state']=='affected' else 'ran',
              'note': 'Update PR activity is separate from a verified production patch'}
    (state / 'status.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
    return 0 if report['state'] == 'ran' else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--qualify-runtime-recovery', action='store_true')
    args = parser.parse_args()
    args.state.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (args.state / 'run.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit('A maintenance run already owns the lock')
        config = json.loads(args.config.read_text())
        try:
            config = maintain(args.config, config, args.state, args.qualify_runtime_recovery)
        except Exception as error:
            from monitor import atomic, now
            atomic(args.state / 'status.json', {'checkedAt': now(), 'state': 'unknown',
                   'phase': 'maintenance runtime update before credentials', 'errorType': type(error).__name__})
            raise SystemExit('Maintenance runtime update failed; previous runtime retained or recovery requires review')
        if args.qualify_runtime_recovery:
            raise SystemExit(0)
        raise SystemExit(execute(config, args.state, args.dry_run))
