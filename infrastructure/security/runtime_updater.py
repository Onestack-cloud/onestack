#!/usr/bin/env python3
"""Qualified automatic security updates for the maintenance tool's own Node 24.

Application runtimes retain their repository release owners and review gates.
"""
import hashlib
import datetime as dt
import io
import json
from pathlib import Path
import platform
import subprocess
import tarfile
import urllib.request
from monitor import atomic, fetch, floors_for, numeric, NODE_FEED


def candidate_version(current, releases):
    if numeric(current)[0] != 24:
        raise ValueError('Maintenance release qualification only covers Node 24')
    target = floors_for(releases)['24']
    return target if numeric(target) > numeric(current) else current


def download(version, destination):
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('Automatic runtime release qualified only for this Mac architecture')
    numeric(version)
    filename = f'node-v{version}-darwin-arm64.tar.gz'
    base = f'https://nodejs.org/dist/v{version}/'
    with urllib.request.urlopen(base + 'SHASUMS256.txt', timeout=40) as response:
        sums = response.read(100000).decode()
    matches = [line.split()[0] for line in sums.splitlines() if line.split()[-1] == filename]
    if len(matches) != 1:
        raise ValueError('Official runtime checksum unavailable')
    with urllib.request.urlopen(base + filename, timeout=300) as response:
        archive = response.read(150 * 1024 * 1024 + 1)
    if len(archive) > 150 * 1024 * 1024 or hashlib.sha256(archive).hexdigest() != matches[0]:
        raise ValueError('Runtime archive checksum mismatch')
    destination.mkdir(parents=True, exist_ok=True)
    # Extract only the named regular executable, never archive paths or links.
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as tar:
        member = tar.getmember(f'node-v{version}-darwin-arm64/bin/node')
        if not member.isfile():
            raise ValueError('Runtime executable is not a regular file')
        target = destination / 'node'
        target.write_bytes(tar.extractfile(member).read())
        target.chmod(0o755)
    return target, matches[0]


def verify(node, config, expected):
    probe = "const z=require('node:zlib'),a=require('node:assert/strict');a.equal(z.brotliDecompressSync(z.brotliCompressSync(Buffer.from('security-runtime'))).toString(),'security-runtime');console.log(process.versions.node)"
    result = subprocess.run([str(node), '-e', probe], capture_output=True, text=True, timeout=30)
    if result.returncode or result.stdout.strip() != expected:
        raise RuntimeError('Candidate runtime version/Brotli verification failed')
    bot = Path(config['renovate']).parents[3]
    check = subprocess.run([str(node), str(bot / 'verify-braces.mjs')], capture_output=True, timeout=30)
    if check.returncode:
        raise RuntimeError('Maintenance dependency compatibility check failed')
    native = subprocess.run([str(node), '-e', "require('re2')"], cwd=bot, capture_output=True, timeout=30)
    if native.returncode:
        raise RuntimeError('Maintenance native module compatibility check failed')


def activate(config_path, config, node, expected, checksum, drill=False):
    before = config_path.read_bytes()
    previous = json.loads(before)
    updated = {**config, 'node': str(node),
               'toolPath': str(node.parent) + ':' + config['toolPath']}
    receipt = {'checkedAt': dt.datetime.now(dt.timezone.utc).isoformat(),
               'target': expected, 'archiveSha256': checksum, 'previousNode': config['node']}
    verify(node, config, expected)
    try:
        atomic(config_path, updated)
        active = json.loads(config_path.read_text())
        verify(Path(active['node']), active, expected)
        if drill:
            # An intentional post-activation health failure proves restoration.
            raise RuntimeError('Controlled recovery qualification')
        receipt['state'] = 'activated and verified'
        return updated, receipt
    except Exception:
        # Restore only our own candidate; never overwrite a concurrent operator edit.
        active = json.loads(config_path.read_text())
        if active.get('node') != str(node):
            raise RuntimeError('Runtime config changed concurrently; recovery requires review')
        atomic(config_path, previous)
        old_version = subprocess.check_output([previous['node'], '--version'], text=True).strip().lstrip('v')
        verify(Path(previous['node']), previous, old_version)
        if not drill:
            raise
        receipt['state'] = 'controlled rollback verified'
        receipt['restoredNode'] = previous['node']
        return previous, receipt


def maintain(config_path, config, state, drill=False):
    if not config.get('automaticMaintenanceRuntime', False) and not drill:
        return config
    current = subprocess.check_output([config['node'], '--version'], text=True, timeout=15).strip().lstrip('v')
    target = candidate_version(current, fetch(NODE_FEED))
    if target == current and not drill:
        return config
    node, checksum = download(target, state / 'runtimes' / target)
    updated, receipt = activate(config_path, config, node, target, checksum, drill)
    atomic(state / ('runtime-qualification.json' if drill else 'runtime-release.json'), receipt)
    return updated
