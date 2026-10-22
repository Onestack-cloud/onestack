#!/usr/bin/env python3
"""Build isolated runtime candidates. Never stop or replace an application."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request
from monitor import PROBE, atomic, fetch, floors_for, numeric, now, NODE_FEED

UNDICI = {'6':'6.29.1', '7':'7.30.1', '8':'8.12.2'}
ERROR_LOG = None
SMOKE = "const z=require('node:zlib'),a=require('node:assert/strict');a.equal(z.brotliDecompressSync(z.brotliCompressSync(Buffer.from('candidate'))).toString(),'candidate');console.log(process.versions.node)"
UNDICI_SMOKE = """const a=require('node:assert/strict'),h=require('node:http'),z=require('node:zlib'),p=require('node:path');const u=require(p.dirname(process.argv[1]));const s=h.createServer((q,r)=>{r.writeHead(200,{'content-encoding':'br'});r.end(z.brotliCompressSync(Buffer.from('isolated-undici-check')))});s.listen(0,'127.0.0.1',async()=>{try{const r=await u.fetch('http://127.0.0.1:'+s.address().port);a.equal(await r.text(),'isolated-undici-check');console.log('passed')}catch{process.exitCode=1}finally{s.close()}});"""


def command(args, timeout=60):
    p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if p.returncode:
        if ERROR_LOG:
            ERROR_LOG.write_text(p.stderr[-12000:]);ERROR_LOG.chmod(0o600)
        raise RuntimeError('Candidate operation failed: ' + Path(args[0]).name)
    return p.stdout.strip()


def safe_path(path):
    if not re.fullmatch(r'/[A-Za-z0-9_./-]+', path) or '..' in Path(path).parts:
        raise ValueError('Unrecognised image runtime path')
    return path


def prepare(config, output):
    global ERROR_LOG
    ERROR_LOG = output / 'candidate-error.log'
    docker = config.get('dockerCommand', ['docker'])
    floors = floors_for(fetch(NODE_FEED))
    rows = []
    recipes = [{'container':name} for name in config.get('requireNodeContainers', [])]
    recipes += [{'image':image} for image in config.get('extraImages', [])]
    for recipe in recipes:
        try:
            if 'container' in recipe:
                name = recipe['container']
                image = command(docker + ['inspect','--format','{{.Image}}',name])
                probe = json.loads(command(docker + ['exec','-e','NODE_OPTIONS=',name,'node','-e',PROBE]))
            else:
                name = recipe['image']
                image = command(docker + ['image','inspect','--format','{{.Id}}',name])
                probe = json.loads(command(docker + ['run','--rm','--network','none','--memory','256m','--cpus','0.5',
                                                    '--entrypoint','node',image,'-e',PROBE]))
            if not re.fullmatch('sha256:[a-f0-9]{64}', image):
                raise ValueError('Image identity unavailable')
            target = floors[str(numeric(probe['node'])[0])]
            external = [item for item in probe['external'] if item['version'].split('.')[0] in UNDICI
                        and numeric(item['version']) < numeric(UNDICI[item['version'].split('.')[0]])]
            if numeric(target) <= numeric(probe['node']) and not external:
                rows.append({'target':name, 'state':'current', 'image':image});continue
            identity = hashlib.sha256(json.dumps([image,target,external],sort_keys=True).encode()).hexdigest()[:24]
            directory = output/'candidates'/identity;directory.mkdir(parents=True,exist_ok=True)
            receipt = directory/'candidate.json'
            if receipt.exists():
                prior = json.loads(receipt.read_text())
                if prior.get('state') == 'candidate verified' and prior.get('verificationRevision')==2:
                    existing=subprocess.run(docker+['image','inspect','--format','{{.Id}}',prior['tag']],capture_output=True,text=True,timeout=30)
                    if existing.returncode==0 and existing.stdout.strip()==prior['candidateImage']:
                        rows.append(prior);continue
            runtime = 'node:' + target + ('-alpine' if probe['alpine'] else '-bookworm-slim')
            command(docker + ['pull',runtime],600)
            runtime_id = command(docker + ['image','inspect','--format','{{.Id}}',runtime])
            base_tag = 'local/security-base:' + image.split(':')[1]
            runtime_tag = 'local/security-runtime:' + runtime_id.split(':')[1]
            command(docker + ['tag',image,base_tag])
            command(docker + ['tag',runtime_id,runtime_tag])
            text = 'FROM ' + runtime_tag + ' AS runtime\nFROM ' + base_tag + '\n'
            text += 'COPY --from=runtime /usr/local/bin/node ' + safe_path(probe['execPath']) + '\n'
            for i,item in enumerate(external):
                version = UNDICI[item['version'].split('.')[0]]
                metadata = fetch('https://registry.npmjs.org/undici/' + version)
                url = metadata['dist']['tarball']
                if not url.startswith('https://registry.npmjs.org/undici/-/'):
                    raise ValueError('Unexpected package publisher')
                with urllib.request.urlopen(url,timeout=60) as response: archive=response.read(5*1024*1024+1)
                integrity = 'sha512-' + base64.b64encode(hashlib.sha512(archive).digest()).decode()
                if len(archive)>5*1024*1024 or integrity != metadata['dist']['integrity']:
                    raise ValueError('Undici archive integrity mismatch')
                # Verify archive members before Docker's local ADD extraction.
                import tarfile,io
                with tarfile.open(fileobj=io.BytesIO(archive),mode='r:gz') as tar:
                    for member in tar.getmembers():
                        if not member.name.startswith('package/') or '..' in Path(member.name).parts or not (member.isfile() or member.isdir()):
                            raise ValueError('Unsafe package archive member')
                package = directory/('undici-'+str(i)+'.tgz');package.write_bytes(archive)
                parent = safe_path(str(Path(item['path']).parent.parent))
                # Remove the obsolete copy only inside the staged image layer.
                text += 'USER root\nRUN rm -rf ' + parent + '/undici\n'
                text += 'ADD ' + package.name + ' /tmp/security-undici-' + str(i) + '/\n'
                text += 'RUN mv /tmp/security-undici-' + str(i) + '/package ' + parent + '/undici\n'
            user = command(docker + ['image','inspect','--format','{{.Config.User}}',image])
            if user:
                if not re.fullmatch('[A-Za-z0-9_:-]+',user):raise ValueError('Unexpected image user')
                text += 'USER ' + user + '\n'
            (directory/'Dockerfile').write_text(text)
            tag = 'local/security-candidate:' + identity
            if command(docker + ['image','inspect','--format','{{.Id}}',base_tag]) != image or command(docker + ['image','inspect','--format','{{.Id}}',runtime_tag]) != runtime_id:
                raise RuntimeError('Candidate source tag changed')
            command(docker + ['build','--network','none','--tag',tag,str(directory)],1200)
            actual = command(docker + ['run','--rm','--network','none','--memory','256m','--cpus','0.5',
                                       '--entrypoint',probe['execPath'],tag,'-e',SMOKE])
            if actual != target:raise RuntimeError('Candidate runtime verification failed')
            candidate = json.loads(command(docker + ['run','--rm','--network','none','--memory','256m','--cpus','0.5',
                                                     '--entrypoint',probe['execPath'],tag,'-e',PROBE]))
            for item in external:
                if not any(x['path']==item['path'] and x['version']==UNDICI[item['version'].split('.')[0]] for x in candidate['external']):
                    raise RuntimeError('Candidate standalone Undici verification failed')
                result=command(docker+['run','--rm','--network','none','--memory','256m','--cpus','0.5',
                                      '--entrypoint',probe['execPath'],tag,'-e',UNDICI_SMOKE,item['path']])
                if result!='passed':raise RuntimeError('Candidate standalone Undici HTTP/Brotli check failed')
            row = {'target':name,'state':'candidate verified','baseImage':image,'tag':tag,
                   'candidateImage':command(docker + ['image','inspect','--format','{{.Id}}',tag]),
                   'node':actual,'external':candidate['external'],'verificationRevision':2,
                   'release':'review required; live application untouched'}
            atomic(receipt,row);rows.append(row)
        except Exception as error:
            rows.append({'target':recipe.get('container',recipe.get('image')),'state':'unknown','errorType':type(error).__name__})
    return {'checkedAt':now(), 'state':'unknown' if any(x['state']=='unknown' for x in rows) else
            'review required' if any(x['state']=='candidate verified' for x in rows) else 'checked', 'targets':rows}


if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--config',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();report=prepare(json.loads(args.config.read_text()),args.output)
    atomic(args.output/'candidates.json',report);print(json.dumps({'state':report['state'],'targets':len(report['targets'])}))
    raise SystemExit(1 if report['state']=='unknown' else 0)
