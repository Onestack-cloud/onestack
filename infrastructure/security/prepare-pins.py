#!/usr/bin/env python3
"""Open reviewed same-major Node version/checksum updates from trusted local code."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('runtime_pins',HERE/'runtime-pins.py')
pins=importlib.util.module_from_spec(spec);spec.loader.exec_module(pins)


def run(args, env, cwd=None):
    p=subprocess.run(args,cwd=cwd,env=env,capture_output=True,text=True,timeout=300)
    if p.returncode:raise RuntimeError('Pinned runtime source preparation failed: '+args[0])
    return p.stdout.strip()


def prepare(repository, profile, env):
    if not repository.get('nodeDownloadPins'):return {'state':'not applicable'}
    repo=repository['repository'];platform=repository['platform']
    cli='glab' if platform=='gitlab' else 'gh'
    with tempfile.TemporaryDirectory(prefix='node-download-pins-') as temporary:
        root=Path(temporary)/'source'
        run([cli,'repo','clone',repo,str(root),'--','--single-branch','--branch','main'],env)
        if not (root/'.security/node-downloads.json').is_file():
            return {'state':'awaiting repository configuration','repository':repo}
        report=pins.inspect(root,prepare=True)
        if not report['changed']:return {'state':'current','repository':repo}
        versions=[]
        for item in json.loads((root/'.security/node-downloads.json').read_text())['downloads']:
            import re
            versions+=re.findall(item['versionPattern'],(root/item['file']).read_text())
        target=sorted(set(versions))
        if len(target)!=1:raise RuntimeError('Mixed runtime update requires review')
        branch='security/node-runtime-'+target[0]
        if run(['git','ls-remote','origin','refs/heads/'+branch],env,root):
            return {'state':'existing update branch','repository':repo,'branch':branch}
        run(['git','switch','-c',branch],env,root)
        run(['git','add','--',*report['changed']],env,root)
        run(['git','-c','user.name=Security maintenance','-c','user.email=security-maintenance@users.noreply.github.com',
             'commit','-m','security: update Node runtime and verified download checksum to '+target[0]],env,root)
        run(['git','push','--set-upstream','origin',branch],env,root)
        body=Path(temporary)/'body.txt'
        body.write_text('Update the registered Node download and its SHA-256 together using the official release manifest.\n\n'
                        'Existing security checks, application tests, review and production release approvals remain required. '
                        'Verify the actual deployed executable and retain the previous release for recovery.\n')
        title='security: update bundled Node to '+target[0]
        if platform=='github':
            url=run(['gh','pr','create','--repo',repo,'--base','main','--head',branch,'--title',title,'--body-file',str(body)],env,root)
        else:
            # glab accepts the full description as one structured argv value.
            url=run(['glab','mr','create','--repo',repo,'--target-branch','main','--source-branch',branch,'--title',title,'--description',body.read_text(),'--yes'],env,root)
        return {'state':'review required','repository':repo,'url':url.splitlines()[-1]}
