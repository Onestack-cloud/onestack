import contextlib
import io
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


class MacInstallerCredentialContinuityTests(unittest.TestCase):
    def test_reinstallation_preserves_existing_auth_pins_and_installs_the_bridge(self):
        source=Path(__file__).with_name('install-mac.py')
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory);(home/'Library').mkdir();base=home/'.local/share/security-maintenance';base.mkdir(parents=True)
            previous={'cloudflareBuildsCredentialRefs':{'synthetic-account':{'secretName':'EXISTING_REFERENCE'}},
                      'cloudflareCliAuthModule':'/synthetic/existing-cf-module.mjs',
                      'cloudflareCliAuthModuleSha256':'a'*64,'executionMode':'monitor-only','updateRunnerHost':'existing-host'}
            (base/'bot-policy.json').write_text(json.dumps(previous))
            def copy_selected(src,dst):
                src=Path(src);dst=Path(dst)
                dst.write_bytes(src.read_bytes() if src.name=='cloudflare-cli-auth.mjs' else b'synthetic installer fixture')
            args=[str(source),'--node',str(home/'node/bin/node'),'--bun',str(home/'bun/bin/bun')]
            with patch('pathlib.Path.home',return_value=home),patch('shutil.copyfile',side_effect=copy_selected),\
                 patch('shutil.copytree'),patch('subprocess.run',return_value=subprocess.CompletedProcess([],0)),\
                 patch.object(sys,'argv',args),contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(source),run_name='__main__')
            current=json.loads((base/'bot-policy.json').read_text())
            for key,value in previous.items():self.assertEqual(current[key],value)
            self.assertEqual((base/'cloudflare-cli-auth.mjs').read_bytes(),source.with_name('cloudflare-cli-auth.mjs').read_bytes())
            self.assertEqual((base/'bot-policy.json').stat().st_mode & 0o777,0o600)
