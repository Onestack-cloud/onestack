#!/usr/bin/env python3
"""Reproducible local scheduler setup; uses existing gh/glab profiles at run time."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

HERE = Path(__file__).resolve().parent

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--node', type=Path, required=True)
    parser.add_argument('--bun', type=Path, required=True)
    args = parser.parse_args()
    base = Path.home() / '.local/share/security-maintenance'
    state = Path.home() / '.local/state/security-maintenance'
    base.mkdir(mode=0o700, parents=True, exist_ok=True)
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    for name in ['monitor.py', 'runtime_updater.py', 'run-bot.py', 'mac-policy.json', 'prepare-pins.py', 'runtime-pins.py', 'providers.py', 'source-monitor.py', 'deploy.py', 'browser-builds.md']:
        shutil.copyfile(HERE / name, base / name)
    shutil.copytree(HERE / 'bot', base / 'bot', dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('node_modules'))
    environment = dict(os.environ)
    environment['PATH'] = str(args.node.parent) + ':' + str(args.bun.parent) + ':' + environment['PATH']
    subprocess.run([str(args.bun), 'install', '--frozen-lockfile', '--ignore-scripts'], cwd=base/'bot', env=environment, check=True)
    subprocess.run([str(args.node), str(base/'bot/install-re2.mjs')], env=environment, check=True)
    config = {'node': str(args.node), 'bun': str(args.bun),
              'renovate': str(base/'bot/node_modules/renovate/dist/renovate.js'),
              'toolPath': environment['PATH'],
              'repositories': json.loads((HERE/'estate.json').read_text())['repositories'],
              'automaticMaintenanceRuntime': False}
    path = base/'bot-policy.json'
    if path.exists():
        config['cloudflareBuildsCredentialRefs']=json.loads(path.read_text()).get('cloudflareBuildsCredentialRefs',{})
    path.write_text(json.dumps(config, indent=2)+'\n');path.chmod(0o600)
    subprocess.run(['/usr/bin/python3', str(base/'run-bot.py'), '--config', str(path), '--state', str(state/'bot'), '--qualify-runtime-recovery'], env=environment, check=True)
    config['automaticMaintenanceRuntime']=True
    path.write_text(json.dumps(config,indent=2)+'\n')
    agents = Path.home()/'Library/LaunchAgents';agents.mkdir(exist_ok=True)
    for suffix, command in [
        ('runtime', [str(base/'monitor.py'), 'runtime', '--config', str(base/'mac-policy.json'), '--output', str(state/'mac')]),
        ('update-bot', [str(base/'run-bot.py'), '--config', str(path), '--state', str(state/'bot')]),
    ]:
        label = 'com.digitalnachos.security-' + suffix
        plist = {'Label': label, 'ProgramArguments': ['/usr/bin/python3', *command], 'StartInterval':3600,
                 'RunAtLoad':False, 'ProcessType':'Background', 'Nice':15, 'LowPriorityIO':True,
                 'EnvironmentVariables': {'PATH':environment['PATH']},
                 'StandardOutPath':str(state/(label+'.log')), 'StandardErrorPath':str(state/(label+'.error.log'))}
        target = agents/(label+'.plist')
        target.write_bytes(plistlib.dumps(plist))
        domain = 'gui/' + str(os.getuid())
        subprocess.run(['launchctl', 'bootout', domain+'/'+label], capture_output=True)
        subprocess.run(['launchctl', 'bootstrap', domain, str(target)], check=True)
    print('Installed two hourly agents; VPS detection remains independent')
