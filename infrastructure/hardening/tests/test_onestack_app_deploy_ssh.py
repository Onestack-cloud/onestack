"""Regression checks for the restricted CI SSH command surface."""

import importlib.machinery
import importlib.util
import os
import pathlib
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "scripts/onestack-app-deploy-ssh"
loader = importlib.machinery.SourceFileLoader("onestack_app_deploy_ssh", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
deploy = importlib.util.module_from_spec(spec)
loader.exec_module(deploy)


class ClassifyTests(unittest.TestCase):
    SHA = "c12d1d091d585280cfff910f47918dcf1a9c1d2f"

    def test_allbids_accepts_only_a_fixed_command_and_full_commit_sha(self):
        self.assertEqual(
            deploy.classify("allbids", f"onestack-deploy allbids {self.SHA}"),
            ("deploy", "allbids", self.SHA),
        )
        self.assertIsNone(deploy.classify("allbids", "onestack-deploy allbids main"))
        self.assertIsNone(deploy.classify("allbids", "onestack-deploy allbids " + self.SHA[:8]))
        self.assertIsNone(
            deploy.classify("allbids", f"onestack-deploy allbids {self.SHA}; id")
        )

    def test_allbids_cannot_rewrite_secrets_or_run_docker(self):
        self.assertIsNone(
            deploy.classify(
                "allbids",
                "printf '%s\\n' 'MIX_ENV=prod' > ~/allbids_app/.env.production",
            )
        )
        self.assertIsNone(
            deploy.classify("allbids", "cd ~/allbids_app && docker compose up -d --pull always")
        )
        self.assertIsNone(deploy.classify("allbids", "docker image prune -af"))

    def test_other_app_commands_remain_available_only_to_their_key(self):
        self.assertEqual(
            deploy.classify("onestack", "onestack-deploy onestack"),
            ("deploy", "onestack", None),
        )
        self.assertIsNone(
            deploy.classify("onestack", f"onestack-deploy allbids {self.SHA}")
        )
        self.assertEqual(
            deploy.classify("allbids", "onestack-deploy-check"),
            ("check", ["allbids"], None),
        )

    def test_backup_retention_ignores_other_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            for day in range(1, 5):
                backup = directory / f"pre-{self.SHA}-202609{day:02d}T010000Z.db"
                backup.touch()
                os.utime(backup, (day, day))
            unrelated = directory / "manual-backup.db"
            unrelated.touch()

            deploy.prune_allbids_backups(directory)

            self.assertFalse((directory / f"pre-{self.SHA}-20260901T010000Z.db").exists())
            self.assertEqual(len(list(directory.glob("pre-*.db"))), 3)
            self.assertTrue(unrelated.exists())


if __name__ == "__main__":
    unittest.main()
