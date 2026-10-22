#!/usr/bin/env python3
"""Validate or prepare registered Node download/checksum pairs. No package scripts."""
import argparse
import json
from pathlib import Path
import re
import http.client


def get(path):
    if not re.fullmatch(r'/dist/(?:index\.json|v\d+\.\d+\.\d+/SHASUMS256\.txt)',path):
        raise ValueError('Unregistered official Node resource')
    connection=http.client.HTTPSConnection('nodejs.org',timeout=40)
    try:
        connection.request('GET',path,headers={'User-Agent':'Onestack-Security/1'})
        response=connection.getresponse()
        data=response.read(2*1024*1024+1)
        if response.status!=200 or len(data)>2*1024*1024:
            raise ValueError('Official Node resource unavailable or incomplete')
        return data.decode()
    finally:
        connection.close()


def checksum(version, artifact):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or artifact != 'linux-x64.tar.xz':
        raise ValueError('Unregistered Node download format')
    name = 'node-v' + version + '-' + artifact
    found = [line.split()[0] for line in get('/dist/v' + version + '/SHASUMS256.txt').splitlines()
             if line.split()[-1] == name]
    if len(found) != 1 or not re.fullmatch(r'[a-f0-9]{64}', found[0]):
        raise ValueError('Official Node checksum incomplete')
    return found[0]


def replace_group(text, pattern, value):
    return re.sub(pattern, lambda m: m.group(0)[:m.start(1)-m.start()] + value + m.group(0)[m.end(1)-m.start():], text)


def inspect(root, prepare=False):
    manifest = root / '.security/node-downloads.json'
    if not manifest.exists():
        return {'state': 'checked', 'downloads': [], 'changed': []}
    releases = json.loads(get('/dist/index.json'))
    floors = {'22':'22.23.4', '24':'24.22.1', '26':'26.12.1'}
    for release in releases:
        if not isinstance(release.get('security'), bool):
            raise ValueError('Node release coverage incomplete')
        if release['security']:
            value = release['version'].lstrip('v');major = value.split('.')[0]
            if major not in floors or tuple(map(int,value.split('.'))) > tuple(map(int,floors[major].split('.'))):
                floors[major] = value
    rows, changed = [], []
    for item in json.loads(manifest.read_text())['downloads']:
        path = (root/item['file']).resolve()
        if not path.is_relative_to(root.resolve()):
            raise ValueError('Download pin escapes repository')
        text = path.read_text()
        versions = set(re.findall(item['versionPattern'], text))
        hashes = set(re.findall(item['checksumPattern'], text))
        if len(versions) != 1 or len(hashes) != 1:
            raise ValueError('Download version/checksum extraction is ambiguous')
        version = versions.pop();digest = hashes.pop()
        if checksum(version, item['artifact']) != digest:
            raise ValueError('Node version and official download checksum do not match')
        if version.split('.')[0] != str(item['major']):
            raise ValueError('Node download major requires review')
        target = floors[str(item['major'])]
        if tuple(map(int,version.split('.'))) < tuple(map(int,target.split('.'))):
            if prepare:
                updated = replace_group(text, item['versionPattern'], target)
                updated = replace_group(updated, item['checksumPattern'], checksum(target,item['artifact']))
                path.write_text(updated);changed.append(item['file'])
            else:
                rows.append({'file':item['file'], 'state':'affected', 'version':version, 'requires':target})
        else:
            rows.append({'file':item['file'], 'state':'checked', 'version':version})
    return {'state':'affected' if any(x['state']=='affected' for x in rows) else 'checked', 'downloads':rows, 'changed':changed}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path.cwd())
    parser.add_argument('--prepare', action='store_true')
    args = parser.parse_args()
    try:
        result = inspect(args.root.resolve(), args.prepare)
    except Exception as error:
        print(json.dumps({'state':'unknown','errorType':type(error).__name__}));raise SystemExit(2)
    print(json.dumps(result))
    raise SystemExit(0 if result['state']=='checked' else 1)
