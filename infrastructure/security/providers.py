#!/usr/bin/env python3
"""Read-only provider drift and live runtime evidence using existing local logins."""
import json
from pathlib import Path
import re
import shlex
import subprocess
import time
import urllib.request
from monitor import atomic, assess, floors_for, fetch, now, NODE_FEED, SCHEDULE

ACCOUNT='663b85e4f509df63c1735f6e77db4370'


def cli(args):
    p=subprocess.run(args,capture_output=True,text=True,timeout=90)
    if p.returncode:raise RuntimeError('Existing provider session unavailable')
    return json.loads(p.stdout)


def request(url, headers, data=None):
    req=urllib.request.Request(url,headers=headers,data=json.dumps(data).encode() if data else None)
    with urllib.request.urlopen(req,timeout=60) as response:return json.load(response)


def azure():
    app=['-g','rg-finnance-app-dev','-n','financial-engine']
    settings=cli(['az','webapp','config','show',*app,'-o','json'])
    expected='/home/site/wwwroot/.runtime/node --no-maglev-osr /home/site/wwwroot/server.js'
    if settings.get('appCommandLine')!=expected:raise ValueError('Azure startup executable drift')
    # Runs inside the main app container. Returns executable metadata only.
    started=time.time()
    code="""const fs=require('node:fs'),cp=require('node:child_process');const env={PATH:'/usr/bin:/bin'};const processes=[];for(const pid of fs.readdirSync('/proc').filter(x=>/^\\d+$/.test(x)&&Number(x)!==process.pid)){try{const exe='/proc/'+pid+'/exe';if(fs.readlinkSync(exe).replace(/ \\(deleted\\)$/,'').endsWith('/node')){processes.push({pid:Number(pid),node:cp.execFileSync(exe,['--version'],{env,timeout:5000}).toString().trim().slice(1)})}}catch{}}const packageInfo=JSON.parse(fs.readFileSync('/home/site/wwwroot/.runtime/security.json'));fs.writeFileSync('/home/security-runtime-metadata.json',JSON.stringify({checkedAt:new Date().toISOString(),packaged:process.versions.node,sourceCommit:packageInfo.source_commit,processes}),{mode:0o600});"""
    command=shlex.join(['/home/site/wwwroot/.runtime/node','--no-maglev-osr','-e',code])
    cli(['az','webapp','exec',*app,'--mode','execute','--command',command,'-o','json'])
    auth=cli(['az','account','get-access-token','--resource','https://management.azure.com/','-o','json'])['accessToken']
    url='https://financial-engine.scm.azurewebsites.net/api/vfs/security-runtime-metadata.json'
    # Kudu reads the shared metadata receipt, never a database or app environment.
    result=None
    for attempt in range(10):
        try:
            result=request(url,{'Authorization':'Bearer '+auth})
            import datetime as dt
            if dt.datetime.fromisoformat(result['checkedAt'].replace('Z','+00:00')).timestamp()<started-5:
                raise ValueError('Azure probe receipt is stale')
            break
        except Exception:
            if attempt==9:raise
            time.sleep(2)
    if not result.get('processes') or not re.fullmatch('[a-f0-9]{40}',result.get('sourceCommit','')):
        raise ValueError('Azure live runtime coverage incomplete')
    return {'target':'Azure Financial Engine','state':'checked','providerMajor':settings['linuxFxVersion'],**result}


def cloudflare_token():
    # Existing Wrangler OAuth remains local. Never copy it into the source or VPS.
    for path in [Path.home()/'.wrangler/config/default.toml',Path.home()/'Library/Preferences/.wrangler/config/default.toml']:
        if path.exists():
            match=re.search(r'^oauth_token\s*=\s*"([^\"]+)"',path.read_text(),re.M)
            if match:return match[1]
    raise RuntimeError('Existing Cloudflare login unavailable')


def cloudflare_pages():
    headers={'Authorization':'Bearer '+cloudflare_token()}
    result=request('https://api.cloudflare.com/client/v4/accounts/'+ACCOUNT+'/pages/projects/kotsovolos-stocktake',headers)
    if not result.get('success'):raise RuntimeError('Pages inventory unavailable')
    return [{'target':'Cloudflare Pages Stocktake '+env,'state':'checked',
             'node':value.get('env_vars',{}).get('NODE_VERSION',{}).get('value')}
            for env,value in result['result']['deployment_configs'].items()]


def cloudflare_builds():
    headers={'Authorization':'Bearer '+cloudflare_token()}
    def get(account,path):
        result=request('https://api.cloudflare.com/client/v4/accounts/'+account+path,headers)
        if not result.get('success'):raise RuntimeError('Provider API coverage incomplete')
        return result['result']
    rows=[]
    for account,script,owner in [(ACCOUNT,'r4r-next-js','RunBuddy'),('c60c6c3daaa4fd10a7f1aa3f7301d202','usual-suspects','Usual Suspects')]:
        try:
            scripts=get(account,'/workers/scripts')
            worker=next(x for x in scripts if x['id']==script)
            triggers=get(account,'/builds/workers/'+worker['tag']+'/triggers')
            if not isinstance(triggers,list) or not triggers:raise ValueError('Build trigger inventory incomplete')
            for trigger in triggers:
                variables=get(account,'/builds/triggers/'+trigger['trigger_uuid']+'/environment_variables')
                rows.append({'target':'Cloudflare Workers Builds '+owner,'state':'checked',
                             'trigger':trigger['trigger_uuid'],'node':variables.get('NODE_VERSION',{}).get('value')})
        except Exception as error:
            rows.append({'target':'Cloudflare Workers Builds '+owner,'state':'unknown','errorType':type(error).__name__,'httpStatus':getattr(error,'code',None)})
    return rows


def runner():
    entries=cli(['gh','api','repos/curiousgeorgios/run-buddy-organizer/actions/runners/downloads'])
    filename=next(x['filename'] for x in entries if x['os']=='linux' and x['architecture']=='x64')
    match=re.fullmatch(r'actions-runner-linux-x64-(\d+\.\d+\.\d+)\.tar\.gz',filename)
    if not match:raise ValueError('Runner version unavailable')
    offered=match[1]
    return {'target':'RunBuddy self-hosted runner','installed':'2.337.0','offered':offered,
            'state':'checked' if offered=='2.337.0' else 'review required',
            'owner':'Nomad CI controller; preserve self-update exclusion and check GitHub enforcement deadline'}


def scan(output):
    rows=[];floors=floors_for(fetch(NODE_FEED));schedule=fetch(SCHEDULE);date=now()[:10]
    for name,operation in [('Azure Financial Engine',azure),('Cloudflare Pages settings',cloudflare_pages),
                           ('Cloudflare Workers Builds settings',cloudflare_builds),('RunBuddy runner release',runner)]:
        try:
            result=operation();rows.extend(result if isinstance(result,list) else [result])
        except Exception as error:
            rows.append({'target':name,'state':'unknown','errorType':type(error).__name__,
                         'httpStatus':getattr(error,'code',None)})
    for row in rows:
        values=[row['node']] if 'node' in row else ([row['packaged']]+[p['node'] for p in row['processes']] if 'packaged' in row else [])
        for value in values:
            try:detail=assess(value,floors,schedule,date)
            except (TypeError,ValueError):detail='provider runtime version unavailable'
            if detail:row.update({'state':'affected','detail':detail})
    report={'checkedAt':now(),'state':'unknown' if any(x['state']=='unknown' for x in rows) else
            'affected' if any(x['state']!='checked' for x in rows) else 'checked','targets':rows}
    atomic(output/'providers.json',report)
    return report


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    print(json.dumps(scan(args.output)))
