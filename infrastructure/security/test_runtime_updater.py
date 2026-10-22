import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from runtime_updater import candidate_version, activate
from enrol import enrol


class MaintenanceReleaseTests(unittest.TestCase):
    def test_release_selection_preserves_major_and_never_downgrades(self):
        releases=[{'version':'v24.23.1','security':True},{'version':'v26.12.1','security':True}]
        self.assertEqual(candidate_version('24.22.1',releases),'24.23.1')
        self.assertEqual(candidate_version('24.24.0',releases),'24.24.0')
        with self.assertRaises(ValueError):candidate_version('26.12.1',releases)

    def test_failed_post_activation_check_restores_previous_runtime(self):
        with tempfile.TemporaryDirectory() as folder:
            config=Path(folder)/'config.json';old={'node':'/known-good/node','toolPath':'/known-good'}
            config.write_text(json.dumps(old))
            with patch('runtime_updater.verify',side_effect=[None,RuntimeError('health failed'),None]), patch('runtime_updater.subprocess.check_output',return_value='v24.22.1\n'):
                with self.assertRaises(RuntimeError):activate(config,old,Path('/candidate/node'),'24.23.1','sha256')
            self.assertEqual(json.loads(config.read_text()),old)

    def test_recovery_never_overwrites_a_concurrent_operator_change(self):
        with tempfile.TemporaryDirectory() as folder:
            config=Path(folder)/'config.json';old={'node':'/known-good/node','toolPath':'/known-good'}
            config.write_text(json.dumps(old));calls=[]
            def verification(*args):
                calls.append(True)
                if len(calls)==2:
                    config.write_text(json.dumps({'node':'/operator/node','toolPath':'/operator'}))
                    raise RuntimeError('changed during verification')
            with patch('runtime_updater.verify',side_effect=verification):
                with self.assertRaisesRegex(RuntimeError,'concurrently'):activate(config,old,Path('/candidate/node'),'24.23.1','sha256')
            self.assertEqual(json.loads(config.read_text())['node'],'/operator/node')

    def test_enrolment_refuses_existing_policy_without_partial_writes(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'renovate.json').write_text('{}')
            with self.assertRaises(ValueError):enrol(root,'owner/repo','github',['.'])
            self.assertFalse((root/'.security').exists())

    def test_new_repository_gets_download_checks_and_application_review(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);enrol(root,'owner/repo','github',['.'])
            policy=json.loads((root/'.security/policy.json').read_text())
            self.assertFalse(policy['release']['automaticPatchReleaseQualified'])
            workflow=(root/'.github/workflows/security.yml').read_text()
            self.assertIn('      - run: python3 .security/runtime-pins.py\n      - run: node --test',workflow)
            self.assertTrue((root/'.security/runtime-pins.py').exists())


if __name__=='__main__':unittest.main()
