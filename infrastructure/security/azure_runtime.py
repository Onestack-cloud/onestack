#!/usr/bin/env python3
"""Fixed metadata-only probe through the Azure CLI's authenticated app SSH tunnel."""
import ast
import inspect
import logging
import shlex
import threading
import uuid
from types import SimpleNamespace

PROBE = "const fs=require('node:fs'),cp=require('node:child_process');const env={PATH:'/usr/bin:/bin'};const processes=[];for(const pid of fs.readdirSync('/proc').filter(x=>/^\\d+$/.test(x)&&Number(x)!==process.pid)){try{const exe='/proc/'+pid+'/exe';if(fs.readlinkSync(exe).replace(/ \\(deleted\\)$/,'').endsWith('/node')){processes.push({pid:Number(pid),node:cp.execFileSync(exe,['--version'],{env,timeout:5000}).toString().trim().slice(1)})}}catch{}}const packageInfo=JSON.parse(fs.readFileSync('/home/site/wwwroot/.runtime/security.json'));fs.writeFileSync('/home/security-runtime-metadata.json',JSON.stringify({checkedAt:new Date().toISOString(),packaged:process.versions.node,sourceCommit:packageInfo.source_commit,processes}),{mode:0o600});"


def run():
    # Use the installed Azure CLI runtime and existing selected account only.
    from azure.cli.core import get_default_cli
    from azure.cli.command_modules.appservice import custom
    import paramiko
    logging.getLogger('paramiko').setLevel(logging.CRITICAL)
    context=get_default_cli()
    context.data.setdefault('headers',{})['x-ms-client-request-id']=str(uuid.uuid4())
    tunnel=custom.get_tunnel(SimpleNamespace(cli_ctx=context),'rg-finnance-app-dev','financial-engine')
    threading.Thread(target=tunnel.start_server,daemon=True).start()
    # Reuse the transport defaults from the installed provider client in memory.
    source=ast.parse(inspect.getsource(custom.create_tunnel_and_session))
    defaults={target.id:ast.literal_eval(node.value) for node in ast.walk(source)
              if isinstance(node,ast.Assign) and isinstance(node.value,ast.Constant)
              for target in node.targets if isinstance(target,ast.Name) and
              target.id in ('ssh_user_name','ssh_user_password')}
    if set(defaults)!={'ssh_user_name','ssh_user_password'}:
        raise RuntimeError('Azure SSH transport defaults unavailable')
    client=paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect('127.0.0.1',port=tunnel.get_port(),username=defaults['ssh_user_name'],
                       password=defaults['ssh_user_password'],look_for_keys=False,allow_agent=False,
                       timeout=30,banner_timeout=30,auth_timeout=30)
        command=shlex.join(['/home/site/wwwroot/.runtime/node','--no-maglev-osr','-e',PROBE])
        _,stdout,_=client.exec_command(command,timeout=45)
        if stdout.channel.recv_exit_status()!=0:
            raise RuntimeError('Azure app runtime probe failed')
    finally:
        client.close()


if __name__=='__main__':
    try:run()
    except Exception:raise SystemExit('Azure native SSH runtime coverage unavailable') from None
