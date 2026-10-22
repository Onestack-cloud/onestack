#!/usr/bin/env python3
"""Install only the pinned official scanner executables, checking archive digests."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import os
import tarfile
import urllib.request


def install(manifest, destination, platform):
    destination.mkdir(parents=True, exist_ok=True)
    for name in ['grype', 'syft']:
        item = manifest[name]['platforms'][platform]
        if not item['url'].startswith(f'https://github.com/anchore/{name}/releases/download/'):
            raise ValueError('Unrecognised scanner publisher')
        with urllib.request.urlopen(item['url'], timeout=120) as response:
            archive = response.read(100 * 1024 * 1024 + 1)
        if len(archive) > 100 * 1024 * 1024 or hashlib.sha256(archive).hexdigest() != item['sha256']:
            raise ValueError('Scanner archive digest does not match pinned metadata')
        with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as tar:
            member = tar.getmember(name)
            if not member.isfile():
                raise ValueError('Scanner executable is not a regular file')
            source = tar.extractfile(member)
            if source is None:
                raise ValueError('Scanner executable missing')
            target = destination / (name + '.new')
            target.write_bytes(source.read())
        os.chmod(target, 0o755)
        target.replace(destination / name)
        print(json.dumps({'installed': name, 'version': manifest[name]['version'], 'archiveSha256': item['sha256']}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--platform', choices=['linux_amd64', 'darwin_arm64'], required=True)
    args = parser.parse_args()
    install(json.loads(args.manifest.read_text()), args.destination, args.platform)
