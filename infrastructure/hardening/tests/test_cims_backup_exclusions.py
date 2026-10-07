"""WCS CIMS client data and credentials must not reach the Hetzner Borg repository.

George approved "exclude and purge" on 7 October 2026. Paths come from the
cims-export-worker data-retention document, its systemd units (WorkingDirectory,
EnvironmentFile, log redirection) and the isolation drop-ins in ../systemd
(ReadWritePaths=/opt/cims-export-worker /var/lib/onestack-cims).
"""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess as sp
import tempfile
import unittest

HARDENING = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location('backup_cims_exclusions', HARDENING / 'scripts/onestack-backup.py')
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)

EXAMPLE = json.loads((HARDENING / 'config/backup.example.json').read_text())
PURGE_PLAN = HARDENING / 'reports/wcs-cims-backup-purge-2026-10-07.md'
BORG = shutil.which('borg') or '/opt/homebrew/bin/borg'
RUN = 'var/backups/onestack/runs/2026-10-07t000000z'

# Archive paths as Borg 1.x stores them (no leading slash).
CIMS_FILES = [
    # Runner data directory: SQLite store holding the CIMS session cookie and CSRF token during a run.
    'opt/cims-export-worker/data/cims-export-worker.sqlite',
    'opt/cims-export-worker/data/cims-export-worker.sqlite-wal',
    'opt/cims-export-worker/data/cims-export-worker.sqlite-shm',
    # Emergency manual login code file.
    'opt/cims-export-worker/data/verification-code.txt',
    # CURATION_WORK_DIR can only be under a ReadWritePaths entry when the drop-in applies.
    'opt/cims-export-worker/work/2026-10-02t020000z/merged/fv_risk_assessment.csv',
    'var/lib/onestack-cims/curation/2026-10-02t020000z/demographics.csv',
    # Files the deploy rsync deliberately leaves untouched on the server.
    'opt/cims-export-worker/exports/cims-export-worker-db-20260702.sql',
    'opt/cims-export-worker/.dev.vars',
    # A renamed copy left behind during the move.
    'opt/cims-export-worker.previous/data/cims-export-worker.sqlite',
    # Environment file: CIMS username, password and export API token.
    'etc/cims-export-worker/cims-export-worker.env',
    # Runner log and logrotate copies.
    'var/log/cims-export-worker.log',
    'var/log/cims-export-worker.log.1',
    'var/log/cims-export-worker.log.2.gz',
    # Default curation folders from tempfile.mkdtemp(prefix="wcs-curate-") and R2 download helpers.
    'root/tmp/wcs-curate-k2j3h4/source/demographics.csv',
    'root/tmp/wcs-cims-csv-zip/run/demographics.csv',
    # Near-miss names beside a checkout's data and exports.
    'root/cims-export-worker/data.bak/cims-export-worker.sqlite',
    'root/cims-export-worker/exports-old/run.csv',
    # Copies the backup itself stages: guest files and SQLite snapshots.
    RUN + '/guests/onestack-ci-runner/rootfs/etc/cims-export-worker/cims-export-worker.env',
    RUN + '/guests/onestack-codex/rootfs/opt/cims-export-worker/run-metadata.json',
    RUN + '/sqlite/opt/cims-export-worker/other.sqlite',
    RUN + '/sqlite/var/lib/onestack-cims/cache.db',
    # Checkout copies elsewhere, including inside staged guest files.
    'root/cims-export-worker/data/cims-export-worker.sqlite',
    RUN + '/guests/onestack-codex/rootfs/home/codex/workspace/cims-export-worker/data/cims-export-worker.sqlite',
    RUN + '/guests/onestack-codex/rootfs/home/codex/workspace/cims-export-worker/exports/run.csv',
    RUN + '/guests/onestack-codex/rootfs/home/codex/workspace/cims-export-worker/.dev.vars.prod',
]

KEPT_FILES = [
    'opt/github-actions-runner/compose.yaml',
    'opt/cims-export/notes.txt',
    'opt/other-app/data/app.sqlite',
    'etc/hostname',
    'etc/onestack-backup/config.json',
    'etc/systemd/system/cims-export-worker.service',
    'etc/systemd/system/cims-export-worker.service.d/20-isolation.conf',
    'etc/logrotate.d/cims-export-worker',
    'var/log/syslog',
    'var/lib/onestack-backup/status.json',
    'var/lib/docker/volumes/postgres_data/_data/PG_VERSION',
    'root/allbids_app/data/bread_machine_prod.db',
    'home/george/cims-export-worker/README.md',
    'home/codex/workspace/cims-export-worker/src/vps-runner.ts',
    RUN + '/manifest.json',
    RUN + '/sqlite/root/allbids_app/data/bread_machine_prod.db',
] + [
    # Every guest restore path the backup requires must survive the new patterns
    # (a sample file below each, since some required paths are directories).
    RUN + '/guests/' + name + '/rootfs' + path + '/restore-sample'
    for name, guest in EXAMPLE['guest_backups'].items() for path in guest['required']
]


def manifest():
    return {'sqlite_exports': [{'source': '/root/allbids_app/data/bread_machine_prod.db'}],
            'filesystem_exports': [{'source': '/var/lib/docker/volumes/loki/_data'}],
            'raw_database_exclusions': ['/var/lib/docker/volumes/postgres_data/_data']}


def purge_plan_patterns():
    """The exclusion file the purge plan writes, read from its heredoc."""
    match = re.search(r"cat > \"\$WORK/cims-excludes.txt\" <<'EOF'\n(.*?)\nEOF\n", PURGE_PLAN.read_text(), re.S)
    return match.group(1).splitlines() if match else []


def excludes(cmd):
    return [cmd[i + 1] for i, arg in enumerate(cmd) if arg == '--exclude']


class CreateCommandTests(unittest.TestCase):
    def test_cims_patterns_are_always_excluded_even_when_live_config_omits_them(self):
        cmd = backup.borg_create_command({'exclude': []}, manifest(), 'repo::archive', ['/etc', '/opt'])
        for pattern in backup.CIMS_EXCLUDE_PATTERNS:
            self.assertIn(pattern, excludes(cmd))

    def test_sources_and_existing_exclusions_are_unchanged(self):
        config = {'exclude': ['pp:/root/.cache', 'sh:**/node_modules']}
        sources = ['/root', '/etc', '/opt', '/var/backups/onestack/runs/x']
        cmd = backup.borg_create_command(config, manifest(), 'repo::onestack-x', sources)
        self.assertEqual(cmd[:8], ['borg', 'create', '--stats', '--compression', 'lz4',
                                   '--lock-wait', '60', 'repo::onestack-x'])
        self.assertEqual(cmd[8:8 + len(sources)], sources)
        found = excludes(cmd)
        for pattern in ['pp:/root/.cache', 'sh:**/node_modules',
                        'pp:/root/allbids_app/data/bread_machine_prod.db',
                        'pp:/root/allbids_app/data/bread_machine_prod.db-wal',
                        'pp:/root/allbids_app/data/bread_machine_prod.db-shm',
                        'pp:/var/lib/docker/volumes/loki/_data',
                        'pp:/var/lib/docker/volumes/postgres_data/_data']:
            self.assertIn(pattern, found)
        self.assertEqual(len(found), len(set(found)), 'duplicate exclusions')

    def test_example_config_lists_cims_patterns_and_keeps_opt_and_etc(self):
        for pattern in backup.CIMS_EXCLUDE_PATTERNS:
            self.assertIn(pattern, EXAMPLE['exclude'])
        for source in ['/opt', '/etc', '/root', '/home', '/var/lib/docker/volumes']:
            self.assertIn(source, EXAMPLE['sources'])

    def test_sqlite_snapshots_skip_cims_directories(self):
        paths = backup.sqlite_exclude_paths(EXAMPLE)
        for path in ['/opt/cims-export-worker', '/var/lib/onestack-cims', '/root/allbids_app/data/backups']:
            self.assertIn(path, paths)

    def test_sqlite_snapshot_does_not_copy_a_cims_store_from_a_mounted_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = root / 'opt/cims-export-worker/data'
            data.mkdir(parents=True)
            store = data / 'cims-export-worker.sqlite'
            sp.run(['sqlite3', str(store), 'CREATE TABLE t (x)'], check=True)
            containers = [{'Mounts': [{'RW': True, 'Type': 'bind', 'Source': str(root / 'opt')}]}]
            result = {'sqlite_exports': []}
            backup.snapshot_sqlite(containers, root / 'stage', result,
                                   [str(root / 'opt/cims-export-worker')])
            self.assertEqual(result['sqlite_exports'], [])

    def test_purge_plan_uses_exactly_the_enforced_patterns(self):
        self.assertEqual(purge_plan_patterns(), list(backup.CIMS_EXCLUDE_PATTERNS))
        text = PURGE_PLAN.read_text()
        self.assertIn('--threshold 0', text)
        self.assertIn('--exclude-from "$WORK/cims-excludes.txt"', text)
        self.assertIn('--patterns-from "$WORK/cims-only.patterns"', text)


@unittest.skipUnless(os.path.exists(BORG), 'borg is not installed')
class RealBorgTests(unittest.TestCase):
    """Run the real Borg pattern engine against a disposable local repository."""

    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.root = Path(self.folder.name)
        self.tree = self.root / 'tree'
        for relative in CIMS_FILES + KEPT_FILES:
            target = self.tree / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            marker = b'ZQXCIMSCLIENTDATA' if relative in CIMS_FILES else b'kept'
            target.write_bytes(marker + relative.encode() + b'\n')
        self.env = os.environ.copy()
        self.env.update(BORG_CACHE_DIR=str(self.root / 'cache'), BORG_SECURITY_DIR=str(self.root / 'security'),
                        BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK='yes', TZ='UTC')
        self.repo = str(self.root / 'repository')
        self.borg('init', '--encryption', 'none', self.repo)

    def tearDown(self):
        self.folder.cleanup()

    def borg(self, *args):
        return sp.run([BORG, *args], env=self.env, cwd=self.tree, capture_output=True, check=True, timeout=120)

    def paths(self, archive):
        output = self.borg('list', '--format', '{type} {path}{NL}', self.repo + '::' + archive).stdout.decode()
        return {line[2:] for line in output.splitlines() if line.startswith('-')}

    def physical_markers(self):
        return sum(p.read_bytes().count(b'ZQXCIMSCLIENTDATA')
                   for p in Path(self.repo, 'data').rglob('*') if p.is_file())

    def test_new_archives_omit_cims_data_and_keep_everything_else(self):
        # A container-planted link into the excluded runner tree must not pull its content in.
        link = self.tree / 'var/lib/docker/volumes/planted/_data/cims'
        link.parent.mkdir(parents=True)
        link.symlink_to(self.tree / 'opt/cims-export-worker/data')
        # Run the exact command line the backup builds, with only the binary,
        # repository and source list pointed at the disposable tree.
        cmd = backup.borg_create_command(EXAMPLE, {'sqlite_exports': []},
                                         self.repo + '::onestack-2026-10-08t000000z', sorted(os.listdir(self.tree)))
        self.assertEqual(cmd[:2], ['borg', 'create'])
        cmd[cmd.index('lz4')] = 'none'  # uncompressed so the marker search below is meaningful
        sp.run([BORG, *cmd[1:]], env=self.env, cwd=self.tree, capture_output=True, check=True, timeout=120)
        archived = self.paths('onestack-2026-10-08t000000z')
        self.assertEqual(sorted(set(CIMS_FILES) & archived), [])
        self.assertEqual(sorted(set(KEPT_FILES) - archived), [])
        listing = self.borg('list', '--format', '{type} {path}{NL}',
                            self.repo + '::onestack-2026-10-08t000000z').stdout.decode()
        self.assertIn('l var/lib/docker/volumes/planted/_data/cims', listing.splitlines())
        self.assertEqual(self.physical_markers(), 0)

    def test_purge_removes_cims_data_from_existing_archives_and_frees_it(self):
        sources = sorted(os.listdir(self.tree))
        for name, stamp in [('2026-08-01_12:00', '2026-08-01T12:00:00'),
                            ('onestack-2026-10-06t120000z', '2026-10-06T12:00:00')]:
            self.borg('create', '--compression', 'none', '--timestamp', stamp, self.repo + '::' + name, *sources)
        work = self.root / 'work'
        work.mkdir()
        (work / 'cims-excludes.txt').write_text('\n'.join(purge_plan_patterns()) + '\n')
        (work / 'cims-only.patterns').write_text(
            ''.join('+ ' + p + '\n' for p in purge_plan_patterns()) + '- sh:**\n')
        pattern_args = ['--exclude-from', str(work / 'cims-excludes.txt')]
        listed = self.borg('list', '--format', '{type} {path}{NL}', '--patterns-from', str(work / 'cims-only.patterns'),
                           self.repo + '::2026-08-01_12:00').stdout.decode().splitlines()
        self.assertEqual({line[2:] for line in listed if line.startswith('-')}, set(CIMS_FILES))
        before = json.loads(self.borg('list', '--json', self.repo).stdout)['archives']
        self.assertGreater(self.physical_markers(), 0)

        dry = self.borg('recreate', '--dry-run', '--list', *pattern_args, self.repo)
        excluded = {line[2:] for line in dry.stdout.decode().splitlines() + dry.stderr.decode().splitlines()
                    if line.startswith('x ')}
        self.assertTrue(set(CIMS_FILES) <= excluded)
        self.assertEqual(sorted(set(KEPT_FILES) & excluded), [])
        self.assertEqual(json.loads(self.borg('list', '--json', self.repo).stdout)['archives'], before)

        self.borg('recreate', *pattern_args, self.repo)
        self.borg('compact', '--threshold', '0', self.repo)
        after = json.loads(self.borg('list', '--json', self.repo).stdout)['archives']
        self.assertEqual([(a['name'], a['time']) for a in after], [(a['name'], a['time']) for a in before])
        self.assertNotEqual([a['id'] for a in after], [a['id'] for a in before])
        for archive in after:
            remaining = self.borg('list', '--format', '{path}{NL}', '--patterns-from', str(work / 'cims-only.patterns'),
                                  self.repo + '::' + archive['name']).stdout.decode()
            self.assertEqual(remaining, '')
            archived = self.paths(archive['name'])
            self.assertEqual(sorted(set(CIMS_FILES) & archived), [])
            self.assertEqual(sorted(set(KEPT_FILES) - archived), [])
        self.assertEqual(self.physical_markers(), 0)
        self.borg('check', self.repo)

    def test_compaction_frees_nothing_while_the_repository_is_append_only(self):
        self.borg('create', '--compression', 'none', self.repo + '::historical', *sorted(os.listdir(self.tree)))
        self.borg('config', self.repo, 'append_only', '1')
        self.borg('recreate', *[arg for p in backup.CIMS_EXCLUDE_PATTERNS for arg in ('--exclude', p)], self.repo)
        self.borg('compact', '--threshold', '0', self.repo)
        self.assertGreater(self.physical_markers(), 0)
        self.borg('config', self.repo, 'append_only', '0')
        self.borg('compact', '--threshold', '0', self.repo)
        self.assertEqual(self.physical_markers(), 0)


if __name__ == '__main__':
    unittest.main()
