#!/usr/bin/env python3
"""Prepare reviewed Node/checksum updates using native platform APIs.

No repository checkout, Git hook, credential helper or package script is run.
"""
import base64
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.parse

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('runtime_pins',HERE/'runtime-pins.py')
pins=importlib.util.module_from_spec(spec);spec.loader.exec_module(pins)


def api(platform, endpoint, env, data=None, optional=False):
    args=['gh' if platform=='github' else 'glab','api',endpoint]
    if data is not None:
        args+=['--method','POST','-H','Content-Type: application/json','--input','-']
    result=subprocess.run(args,input=json.dumps(data) if data is not None else None,env=env,capture_output=True,text=True,timeout=90)
    if result.returncode:
        if optional and ('HTTP 404' in result.stderr or 'HTTP 404' in result.stdout):return None
        raise RuntimeError('Pinned runtime platform API unavailable')
    return json.loads(result.stdout)


def file_at(platform,prefix,path,sha,env,optional=False):
    if Path(path).is_absolute() or '..' in Path(path).parts:raise ValueError('Unregistered source path')
    escaped=urllib.parse.quote(path,safe='/' if platform=='github' else '')
    endpoint=prefix+('/contents/' if platform=='github' else '/repository/files/')+escaped+'?ref='+sha
    result=api(platform,endpoint,env,optional=optional)
    if result is None:return None
    if result.get('encoding')!='base64':raise ValueError('Source file encoding unavailable')
    content=base64.b64decode(result['content'])
    if len(content)>2*1024*1024:raise ValueError('Source pin file is too large')
    return content


def update_request(platform,prefix,repo,branch,title,body,env):
    if platform=='github':
        head=urllib.parse.quote(repo.split('/')[0]+':'+branch,safe='')
        existing=api(platform,prefix+'/pulls?state=all&head='+head,env)
        if existing:
            return {'state':'review required' if existing[0]['state']=='open' else 'closed update held','url':existing[0]['html_url']}
        result=api(platform,prefix+'/pulls',env,{'base':'main','head':branch,'title':title,'body':body})
        return {'state':'review required','url':result['html_url']}
    existing=api(platform,prefix+'/merge_requests?scope=all&source_branch='+urllib.parse.quote(branch,safe=''),env)
    if existing:
        return {'state':'review required' if existing[0]['state']=='opened' else 'closed update held','url':existing[0]['web_url']}
    result=api(platform,prefix+'/merge_requests',env,{'target_branch':'main','source_branch':branch,'title':title,'description':body})
    return {'state':'review required','url':result['web_url']}


def prepare(repository, profile, env):
    if not repository.get('nodeDownloadPins'):return {'state':'not applicable'}
    repo=repository['repository'];platform=repository['platform']
    prefix='repos/'+repo if platform=='github' else 'projects/'+urllib.parse.quote(repo,safe='')
    ref=api(platform,prefix+('/git/ref/heads/main' if platform=='github' else '/repository/branches/main'),env)
    sha=ref['object']['sha'] if platform=='github' else ref['commit']['id']
    manifest=file_at(platform,prefix,'.security/node-downloads.json',sha,env,optional=True)
    if manifest is None:return {'state':'awaiting repository configuration','repository':repo}
    policy=json.loads(manifest)
    paths=sorted(set(item['file'] for item in policy['downloads']+policy.get('versionFiles',[])))
    originals={path:file_at(platform,prefix,path,sha,env) for path in paths}
    with tempfile.TemporaryDirectory(prefix='node-download-pins-') as temporary:
        root=Path(temporary).resolve();(root/'.security').mkdir()
        (root/'.security/node-downloads.json').write_bytes(manifest)
        for path,content in originals.items():
            destination=(root/path).resolve()
            if not destination.is_relative_to(root):raise ValueError('Pin file escapes temporary source directory')
            destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(content)
        report=pins.inspect(root,prepare=True)
        if not report['changed']:return {'state':'current','repository':repo}
        versions=[]
        for item in policy['downloads']:
            versions+=re.findall(item['versionPattern'],(root/item['file']).read_text())
        versions=sorted(set(versions))
        if len(versions)!=1:raise RuntimeError('Mixed runtime update requires review')
        branch='security/node-runtime-'+versions[0]
        title='security: update Node runtime and verified checksum to '+versions[0]
        body='Update the registered Node download, official SHA-256 and related CI/developer pins together.\n\nExisting tests, review and deployment approvals remain required. Verify actual produced and deployed executables. Custom CI image candidates require their existing controller before rerunning the gate. Retain the known-good release for recovery.\n'
        branch_path=prefix+('/git/ref/heads/' if platform=='github' else '/repository/branches/')+urllib.parse.quote(branch,safe='')
        existing=api(platform,branch_path,env,optional=True)
        if existing is None:
            if platform=='github':
                parent=api(platform,prefix+'/git/commits/'+sha,env)
                tree=api(platform,prefix+'/git/trees',env,{'base_tree':parent['tree']['sha'],
                    'tree':[{'path':path,'mode':'100644','type':'blob','content':(root/path).read_text()} for path in report['changed']]})
                commit=api(platform,prefix+'/git/commits',env,{'message':title,'tree':tree['sha'],'parents':[sha]})
                api(platform,prefix+'/git/refs',env,{'ref':'refs/heads/'+branch,'sha':commit['sha']})
            else:
                actions=[{'action':'update','file_path':path,'encoding':'text','content':(root/path).read_text()} for path in report['changed']]
                api(platform,prefix+'/repository/commits',env,{'branch':branch,'start_sha':sha,'commit_message':title,'actions':actions})
        return {'repository':repo,**update_request(platform,prefix,repo,branch,title,body,env)}
