#!/usr/bin/env python3
"""Collect security report metadata, including affected reports with a passing PR gate."""
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.parse
from monitor import atomic, now


def run(args, env):
    p=subprocess.run(args,env=env,capture_output=True,text=True,timeout=90)
    if p.returncode:raise RuntimeError('Source security report unavailable')
    return p.stdout


def report_from_log(log):
    text='\n'.join(re.sub(r'^(?:[^\t]*\t){2}\d{4}-\d{2}-\d{2}T\S+\s?', '', line) for line in log.splitlines())
    decoder=json.JSONDecoder()
    for match in re.finditer(r'(?:^|\n)(\{)',text):
        try:report=decoder.raw_decode(text[match.start(1):])[0]
        except ValueError:continue
        if isinstance(report,dict) and 'audits' in report and 'gate' in report:return report
    raise ValueError('No complete security report in job log')


def scan(repositories, output):
    rows=[]
    for repository in repositories:
        repo=repository['repository'];env=dict(os.environ)
        if repository['profile']=='wcs':env['GH_CONFIG_DIR']=str(Path.home()/'.config/gh-wcs')
        try:
            if repository['platform']=='github':
                runs=json.loads(run(['gh','api',f'repos/{repo}/actions/workflows/security.yml/runs?branch=main&per_page=1'],env))['workflow_runs']
                if not runs or runs[0]['status']!='completed':raise ValueError('Latest security workflow incomplete')
                latest=runs[0];report=report_from_log(run(['gh','run','view',str(latest['id']),'-R',repo,'--log'],env))
                url=latest['html_url'];commit=latest['head_sha']
            else:
                prefix='projects/'+urllib.parse.quote(repo,safe='')
                pipelines=json.loads(run(['glab','api',prefix+'/pipelines?ref=main&per_page=1'],env))
                if not pipelines:raise ValueError('No main security pipeline')
                latest=pipelines[0]
                jobs=json.loads(run(['glab','api',prefix+'/pipelines/'+str(latest['id'])+'/jobs?per_page=100'],env))
                job=next(x for x in jobs if x['name']=='security-audit' and x['status'] in ['success','failed'])
                report=json.loads(run(['glab','api',prefix+'/jobs/'+str(job['id'])+'/artifacts/security-report.json'],env))
                url=latest['web_url'];commit=latest['sha']
            age=dt.datetime.now(dt.timezone.utc).timestamp()-dt.datetime.fromisoformat(report['checkedAt'].replace('Z','+00:00')).timestamp()
            if not 0<=age<=115200:raise ValueError('Source security inventory is stale')
            if report['state'] not in ['checked','affected']:raise ValueError('Source advisory coverage incomplete')
            rows.append({'repository':repo,'state':report['state'],'checkedAt':report['checkedAt'],'commit':commit,'url':url,
                         'advisories':sorted(set(report.get('existingAdvisories',[])+report.get('introducedAdvisories',[]))),
                         'findings':report.get('findings',[]),'verifiedMitigations':report.get('verifiedMitigations',[])})
        except Exception as error:
            rows.append({'repository':repo,'state':'unknown','errorType':type(error).__name__})
    report={'checkedAt':now(),'state':'unknown' if any(x['state']=='unknown' for x in rows) else
            'affected' if any(x['state']=='affected' for x in rows) else 'checked','repositories':rows}
    atomic(output/'sources.json',report)
    return report
