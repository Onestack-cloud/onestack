"""The root backup must not follow container- or guest-controlled symlinks out of their tree.

Docker volumes, bind mounts and guest filesystems are writable by less trusted
code. A planted symlink or `..` path must never make the backup read, copy,
chown or open a host file outside the intended tree, and must never let data
from an excluded directory (such as the WCS CIMS runner) escape its exclusion.
"""
import importlib.util
import os
from pathlib import Path
import sqlite3
import subprocess as sp
import sys
import tempfile
import time
import unittest
from contextlib import closing

HARDENING = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location('backup_symlink_safety', HARDENING / 'scripts/onestack-backup.py')
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


def make_sqlite(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(path)) as con:
        con.execute('CREATE TABLE t (x)')
        con.commit()


class Fixture(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.base = Path(os.path.realpath(self.folder.name))
        # Stand-ins for host files a container must not be able to reach.
        self.host = self.base / 'host'
        (self.host / 'etc').mkdir(parents=True)
        (self.host / 'etc/shadow.conf').write_text('host secret\n')
        (self.host / 'etc/ssh_host_key.pem').write_text('host key\n')
        make_sqlite(self.host / 'etc/host.db')
        self.cims = self.base / 'opt/cims-export-worker/data'
        make_sqlite(self.cims / 'cims-export-worker.sqlite')
        self.volume = self.base / 'volumes/app/_data'
        self.volume.mkdir(parents=True)
        self.stage = self.base / 'stage'
        self.stage.mkdir()

    def tearDown(self):
        self.folder.cleanup()

    def staged_files(self):
        return sorted(str(p.relative_to(self.stage)) for p in self.stage.rglob('*')
                      if p.is_file() or p.is_symlink())


class ContainmentTests(Fixture):
    def test_resolve_within_rejects_symlink_and_dotdot_escapes(self):
        (self.volume / 'etc').symlink_to(self.host / 'etc')
        (self.volume / 'real.txt').write_text('ok')
        self.assertEqual(backup.resolve_within(self.volume / 'real.txt', self.volume), self.volume / 'real.txt')
        self.assertIsNone(backup.resolve_within(self.volume / 'etc/shadow.conf', self.volume))
        self.assertIsNone(backup.resolve_within(str(self.volume) + '/../../../host/etc/shadow.conf', self.volume))
        self.assertIsNone(backup.resolve_within(self.base / 'volumes/app/_data_sibling', self.volume))

    def test_guest_relative_path_rejects_dotdot(self):
        for value in ['/home/../etc/shadow', '../etc', 'relative', '/']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                backup.guest_relative_path(value)

    def test_borg_create_does_not_follow_symlinks_or_read_special_files(self):
        cmd = backup.borg_create_command({'exclude': []}, {'sqlite_exports': []}, 'repo::a', ['/opt'])
        for flag in ['--read-special', '--follow', '-L']:
            self.assertNotIn(flag, cmd)


class SqliteSnapshotTests(Fixture):
    def snapshot(self, exclude=()):
        manifest = {'sqlite_exports': []}
        containers = [{'Mounts': [{'RW': True, 'Type': 'volume', 'Source': str(self.volume)}]}]
        backup.snapshot_sqlite(containers, self.stage, manifest, exclude)
        return sorted(item['source'] for item in manifest['sqlite_exports'])

    def test_real_database_is_snapshotted(self):
        make_sqlite(self.volume / 'app.db')
        self.assertEqual(self.snapshot(), [str(self.volume / 'app.db')])

    def test_symlinked_directory_to_host_etc_is_not_traversed(self):
        (self.volume / 'etc').symlink_to(self.host / 'etc')
        self.assertEqual(self.snapshot(), [])
        self.assertEqual(self.staged_files(), [])

    def test_symlinked_database_file_and_dotdot_link_are_skipped(self):
        (self.volume / 'stolen.db').symlink_to(self.host / 'etc/host.db')
        (self.volume / 'up').symlink_to('..')
        (self.volume / 'escape.sqlite').symlink_to('../../../host/etc/host.db')
        self.assertEqual(self.snapshot(), [])
        self.assertEqual(self.staged_files(), [])

    def test_excluded_cims_directory_reached_through_a_symlink_stays_excluded(self):
        (self.volume / 'cims').symlink_to(self.cims)
        (self.volume / 'session.sqlite').symlink_to(self.cims / 'cims-export-worker.sqlite')
        self.assertEqual(self.snapshot([str(self.base / 'opt/cims-export-worker')]), [])
        self.assertEqual(self.staged_files(), [])

    def test_mount_whose_real_path_is_excluded_is_skipped(self):
        alias = self.base / 'volumes/alias'
        alias.symlink_to(self.cims)
        manifest = {'sqlite_exports': []}
        containers = [{'Mounts': [{'RW': True, 'Type': 'bind', 'Source': str(alias)}]}]
        backup.snapshot_sqlite(containers, self.stage, manifest, [str(self.base / 'opt/cims-export-worker')])
        self.assertEqual(manifest['sqlite_exports'], [])
        self.assertEqual(self.staged_files(), [])

    def test_file_level_exclusion_skips_only_that_database(self):
        make_sqlite(self.volume / 'keep.db')
        make_sqlite(self.volume / 'nested/old-copy.db')
        excluded = [str(self.volume / 'nested/old-copy.db')]
        self.assertEqual(self.snapshot(excluded), [str(self.volume / 'keep.db')])

    def test_symlink_swapped_in_while_sqlite_opens_is_detected_and_discarded(self):
        make_sqlite(self.volume / 'app.db')
        original = backup.backup_sqlite

        def racing(source, destination, **kwargs):
            # The container replaces the checked file with a link to a host database
            # after the walk validated it and before SQLite opens it by name.
            os.rename(source, str(source) + '.moved')
            os.symlink(self.host / 'etc/host.db', source)
            return original(source, destination, **kwargs)

        backup.backup_sqlite = racing
        try:
            with self.assertRaisesRegex(RuntimeError, 'other than the checked database'):
                self.snapshot()
        finally:
            backup.backup_sqlite = original
        self.assertEqual(self.staged_files(), [])

    def test_live_wal_database_with_an_independent_writer_is_snapshotted(self):
        db = self.volume / 'live.db'
        ready = self.base / 'ready'
        writer = sp.Popen([sys.executable, '-c', (
            'import sqlite3, sys, time, pathlib\n'
            'w = sqlite3.connect(sys.argv[1]); w.execute("PRAGMA journal_mode=WAL")\n'
            'w.execute("PRAGMA wal_autocheckpoint=0"); w.execute("CREATE TABLE t (x)")\n'
            'w.execute("INSERT INTO t VALUES (1)"); w.commit()\n'
            'pathlib.Path(sys.argv[2]).touch(); time.sleep(5)\n'), str(db), str(ready)])
        try:
            deadline = time.monotonic() + 10
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertTrue((self.volume / 'live.db-wal').exists())
            self.assertEqual(self.snapshot(), [str(db)])
            snapshot = self.stage / str(db).lstrip('/')
            with closing(sqlite3.connect(snapshot)) as con:
                self.assertEqual(con.execute('SELECT x FROM t').fetchall(), [(1,)])
        finally:
            writer.kill()
            writer.wait()

    def test_symlinked_wal_sidecar_is_refused(self):
        make_sqlite(self.volume / 'app.db')
        (self.volume / 'app.db-shm').symlink_to(self.host / 'etc/shadow.conf')
        self.assertEqual(self.snapshot(), [])
        self.assertEqual((self.host / 'etc/shadow.conf').read_text(), 'host secret\n')


class ConfigurationCopyTests(Fixture):
    def test_postgres_configuration_copies_only_contained_regular_files(self):
        data = self.volume / 'pgroot/data'
        (data / 'conf.d').mkdir(parents=True)
        (data / 'PG_VERSION').write_text('16\n')
        (data / 'postgresql.conf').write_text('shared_buffers = 1GB\n')
        (data / 'evil.conf').symlink_to(self.host / 'etc/shadow.conf')
        (data / 'conf.d/ok.conf').write_text('work_mem = 4MB\n')
        (data / 'conf.d/evil.conf').symlink_to(self.host / 'etc/shadow.conf')
        (data / 'conf.d/up').symlink_to('../../../../../host/etc')
        containers = [{'_name': 'pg', 'Mounts': [{'Source': str(self.volume), 'Destination': '/var/lib/postgresql/data'}]}]
        manifest = {'database_exports': [{'container': 'pg', 'type': 'postgresql'}]}
        backup.preserve_postgres_configuration(containers, self.stage, manifest)
        self.assertEqual(self.staged_files(), ['pg/PG_VERSION', 'pg/conf.d/ok.conf', 'pg/postgresql.conf'])
        self.assertIn(str(data), manifest['raw_database_exclusions'])

    def test_postgres_data_directory_symlinked_to_host_is_ignored(self):
        (self.host / 'etc/PG_VERSION').write_text('16\n')
        (self.volume / 'pgroot').mkdir()
        (self.volume / 'pgroot/data').symlink_to(self.host / 'etc')
        containers = [{'_name': 'pg', 'Mounts': [{'Source': str(self.volume), 'Destination': '/var/lib/postgresql/data'}]}]
        manifest = {'database_exports': [{'container': 'pg', 'type': 'postgresql'}]}
        backup.preserve_postgres_configuration(containers, self.stage, manifest)
        self.assertEqual(self.staged_files(), [])

    def test_native_export_configuration_never_follows_or_chowns_through_symlinks(self):
        (self.volume / 'conf').mkdir()
        (self.volume / 'conf/my.cnf').write_text('[mysqld]\n')
        (self.volume / 'conf/key.pem').symlink_to(self.host / 'etc/ssh_host_key.pem')
        (self.volume / 'etc').symlink_to(self.host / 'etc')
        (self.volume / 'up').symlink_to('..')
        before = os.lstat(self.host / 'etc/ssh_host_key.pem')
        containers = [{'_name': 'mariadb', 'Mounts': [{'Source': str(self.volume), 'Destination': '/var/lib/mysql'}]}]
        manifest = {'database_exports': [{'container': 'mariadb', 'type': 'mariadb'}]}
        backup.preserve_postgres_configuration(containers, self.stage, manifest)
        self.assertEqual(self.staged_files(), ['mariadb/conf/my.cnf'])
        after = os.lstat(self.host / 'etc/ssh_host_key.pem')
        self.assertEqual((before.st_uid, before.st_gid, before.st_mode), (after.st_uid, after.st_gid, after.st_mode))


class GuestPathTests(Fixture):
    def setUp(self):
        super().setUp()
        self.mount = self.base / 'guest-root'
        (self.mount / 'etc').mkdir(parents=True)
        (self.host / 'home/codex/workspace').mkdir(parents=True)

    def test_contained_guest_path_is_accepted(self):
        (self.mount / 'home/codex/workspace').mkdir(parents=True)
        self.assertEqual(backup.guest_source(self.mount, '/home/codex/workspace'),
                         self.mount / 'home/codex/workspace')

    def test_guest_symlink_component_resolving_to_host_is_refused(self):
        # An absolute symlink inside the mounted guest resolves against the host root.
        (self.mount / 'home').symlink_to(self.host / 'home')
        with self.assertRaisesRegex(RuntimeError, 'outside the guest filesystem'):
            backup.guest_source(self.mount, '/home/codex/workspace')

    def test_guest_relative_symlink_climbing_out_is_refused(self):
        # The final component is a real directory; an intermediate one climbs out.
        (self.host / 'lib/docker').mkdir(parents=True)
        (self.mount / 'var').symlink_to('../host')
        with self.assertRaisesRegex(RuntimeError, 'outside the guest filesystem'):
            backup.guest_source(self.mount, '/var/lib/docker')

    def test_final_component_symlink_and_dotdot_are_refused(self):
        (self.mount / 'root').symlink_to('etc')
        with self.assertRaisesRegex(RuntimeError, 'missing or a symlink'):
            backup.guest_source(self.mount, '/root')
        with self.assertRaises(ValueError):
            backup.guest_source(self.mount, '/etc/../../host/etc')


class HeaderReadTests(Fixture):
    def test_header_read_refuses_symlinks_and_special_files(self):
        (self.stage / 'dump.rdb').symlink_to(self.host / 'etc/shadow.conf')
        self.assertIsNone(backup.read_header(self.stage / 'dump.rdb', 5))
        os.mkfifo(self.stage / 'fifo.rdb')
        self.assertIsNone(backup.read_header(self.stage / 'fifo.rdb', 5))
        (self.stage / 'real.rdb').write_bytes(b'REDIS0011')
        self.assertEqual(backup.read_header(self.stage / 'real.rdb', 5)[0], b'REDIS')

    def test_subdirectory_open_refuses_symlinked_and_dotdot_components(self):
        (self.volume / 'pgroot').symlink_to(self.host)
        (self.volume / 'real/data').mkdir(parents=True)
        fd = os.open(self.volume, os.O_RDONLY | os.O_DIRECTORY)
        try:
            self.assertIsNone(backup.open_subdirectory(fd, 'pgroot/etc'))
            self.assertIsNone(backup.open_subdirectory(fd, '../host'))
            child = backup.open_subdirectory(fd, 'real/data')
            self.assertIsNotNone(child)
            os.close(child)
        finally:
            os.close(fd)


if __name__ == '__main__':
    unittest.main()
