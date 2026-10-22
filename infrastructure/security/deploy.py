#!/usr/bin/env python3
"""Install source-only detection through the existing VPS administration route."""
import argparse
import base64
import json
from pathlib import Path
import subprocess
import time

HERE = Path(__file__).resolve().parent


def guest_execute(guest, code, deadline=180):
    # Credentials and application data never cross this channel.
    wrapper = '''import base64,json,subprocess,time
def call(packet):
 p=subprocess.run(['virsh','qemu-agent-command',guest,json.dumps(packet)],capture_output=True,text=True,timeout=30)
 if p.returncode: raise RuntimeError('Guest agent unavailable')
 return json.loads(p.stdout)['return']
pid=call({'execute':'guest-exec','arguments':{'path':'/usr/bin/python3','arg':['-c',code],'capture-output':True}})['pid']
until=time.monotonic()+deadline
while time.monotonic()<until:
 result=call({'execute':'guest-exec-status','arguments':{'pid':pid}})
 if result.get('exited'):
  print(base64.b64decode(result.get('out-data','')).decode(),end='')
  if result.get('exitcode'):
   raise RuntimeError('Guest operation failed; inspect native service logs')
  break
 time.sleep(2)
else: raise TimeoutError('Guest operation incomplete; inspect before retrying')
'''
    return 'guest=' + repr(guest) + '\ncode=' + repr(code) + '\ndeadline=' + str(deadline) + '\n' + wrapper


def payload(guest=None, scan=False, images=False):
    policy = json.loads((HERE / 'vps-policy.json').read_text())
    if guest:
        policy = {**policy['guests'][guest], 'grype': policy['grype'], 'syft': policy['syft'],
                  'requiredReports': {'images.json': 115200, 'os.json': 115200}}
    modes = ['images', 'os', 'candidates'] if guest else ['runtime', 'images', 'os', 'availability', 'health', 'candidates']
    files = {name: base64.b64encode((HERE / name).read_bytes()).decode()
             for name in ['monitor.py', 'prepare-images.py', 'install-tools.py', 'tools.json']}
    units = {p.name: p.read_text() for p in (HERE / 'systemd').glob('*')
             if any(p.name.startswith('onestack-security-' + mode + '.') for mode in modes)}
    return 'files=' + repr(files) + '\nunits=' + repr(units) + '\npolicy=' + repr(policy) + '\nscan=' + repr(scan) + '\nimages=' + repr(images) + '''
import base64,hashlib,json,subprocess,sys
from pathlib import Path
base=Path('/opt/onestack-security');base.mkdir(parents=True,exist_ok=True)
# Running jobs keep their loaded source and finish normally. The next timer run
# loads the updated detector; installing detection never interrupts an application.
for name,data in files.items(): (base/name).write_bytes(base64.b64decode(data))
config=Path('/etc/onestack-security');config.mkdir(exist_ok=True)
(config/'policy.json').write_text(json.dumps(policy,indent=2)+'\\n')
state=Path('/var/lib/onestack-security');state.mkdir(mode=0o700,exist_ok=True)
manifest=json.loads((base/'tools.json').read_text())
for tool in ['grype','syft']:
 binary=base/'bin'/tool
 if not binary.exists():
  subprocess.run([sys.executable,str(base/'install-tools.py'),'--manifest',str(base/'tools.json'),'--destination',str(base/'bin'),'--platform','linux_amd64'],check=True)
  break
for name,text in units.items(): Path('/etc/systemd/system',name).write_text(text)
subprocess.run(['systemctl','daemon-reload'],check=True)
timers=[name for name in units if name.endswith('.timer')]
subprocess.run(['systemctl','enable','--now',*timers],check=True)
if scan:
 subprocess.run(['systemctl','start','--no-block','onestack-security-os.service'],check=True)
if images:
 subprocess.run(['systemctl','start','--no-block','onestack-security-images.service','onestack-security-candidates.service'],check=True)
print(json.dumps({'installed':True,'monitorSha256':hashlib.sha256((base/'monitor.py').read_bytes()).hexdigest(),'timers':timers,'scanStarted':scan}))
'''


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--guest', choices=list(json.loads((HERE / 'vps-policy.json').read_text())['guests']))
    parser.add_argument('--scan', action='store_true', help='Start the OS scan, leaving image scanning on its timer')
    parser.add_argument('--images', action='store_true', help='Start read-only image scanning and isolated candidate preparation')
    args = parser.parse_args()
    code = payload(args.guest, args.scan, args.images)
    if args.guest:
        code = guest_execute(args.guest, code, 600)
    result = subprocess.run(['ssh', '-o', 'BatchMode=yes', 'onestack-admin', 'python3', '-'], input=code, text=True)
    raise SystemExit(result.returncode)
