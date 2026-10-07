#!/usr/bin/env python3
"""Back up Onestack databases, application files and selected guest data."""
import argparse
from contextlib import closing
import datetime as dt
import fcntl
import gzip
import json
import os
import pwd
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import sqlite3
import stat
import subprocess as sp
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET

CONFIG = Path("/etc/onestack-backup/config.json")
STATE = Path("/var/lib/onestack-backup")
STAGING = Path("/var/backups/onestack/runs")
SECRETS = set()
HULY_RETIRED_SCOPE = "huly-retired-v1"

# WCS CIMS client data and credentials must never reach the Hetzner Storage Box
# ("exclude and purge", approved 7 October 2026). These are enforced even when the
# live configuration omits them. reports/wcs-cims-backup-purge-2026-10-07.md
# removes exactly these patterns from existing archives; keep the two in step.
# Borg 1.x matches archive paths, which have no leading slash.
CIMS_EXCLUDE_PATTERNS = (
    # Runner tree: SQLite session store, emergency code file, any CURATION_WORK_DIR,
    # files the deploy rsync leaves untouched, and renamed copies of the tree.
    "sh:opt/cims-export-worker*",
    # Environment file with the CIMS username, password and export API token.
    "sh:etc/cims-export-worker*",
    # Runner HOME, the only other path its systemd sandbox can write.
    "sh:var/lib/onestack-cims*",
    # Runner log and logrotate copies.
    "sh:var/log/cims-export-worker.log*",
    # Data, exports and credentials in checkouts elsewhere, including staged guest files.
    "sh:**/cims-export-worker/data",
    "sh:**/cims-export-worker/exports",
    "sh:**/cims-export-worker/.dev.vars*",
    # Curation and R2 download working folders created by the runner's helpers.
    "sh:**/wcs-curate-*",
    "sh:**/wcs-cims-*",
)
# Directories never read by the SQLite snapshot, compared on real paths.
CIMS_EXCLUDED_DIRECTORIES = ("/opt/cims-export-worker", "/etc/cims-export-worker", "/var/lib/onestack-cims")
SQLITE_HEADER = b"SQLite format 3\x00"
SQLITE_SUFFIXES = (".db", ".sqlite", ".sqlite3")
CONFIGURATION_SUFFIXES = (".conf", ".cnf", ".acl", ".toml", ".pem")


def resolve_within(path, root):
    """Return the real path of path when it stays inside root's real path, else None."""
    real_root = os.path.realpath(root)
    real = os.path.realpath(path)
    if os.path.commonpath([real_root, real]) != real_root:
        return None
    return Path(real)


def within_any(path, roots):
    return any(os.path.commonpath([root, str(path)]) == root for root in roots)


def walk_files(root):
    """Yield every non-directory entry below root without descending symlinked directories."""
    for directory, _, names in os.walk(root, followlinks=False):
        for name in names:
            yield Path(directory) / name


def open_contained_regular(path, root):
    """Open a regular file read-only without following symlinks or leaving root.

    Returns (fd, stat) or None. The fd's inode must match the inode at the
    contained real path, so swapping a parent directory for a symlink between
    the checks and the open cannot redirect the read outside root.
    """
    try:
        if not stat.S_ISREG(os.lstat(path).st_mode):
            return None  # never open devices, FIFOs or sockets
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    except OSError:
        return None
    try:
        info = os.fstat(fd)
        real = resolve_within(path, root)
        if real is not None and stat.S_ISREG(info.st_mode):
            current = os.lstat(real)
            if (current.st_dev, current.st_ino) == (info.st_dev, info.st_ino):
                return fd, info
    except OSError:
        pass
    os.close(fd)
    return None


def read_contained_header(path, root, size):
    """Read the first bytes of a contained regular file; None if unsafe or missing."""
    opened = open_contained_regular(path, root)
    if opened is None:
        return None
    fd, info = opened
    try:
        return os.read(fd, size), info
    finally:
        os.close(fd)


def copy_contained_file(source, target, root, *, preserve_owner=False):
    """Copy a contained regular file into the stage; symlinks and escapes are skipped."""
    opened = open_contained_regular(source, root)
    if opened is None:
        return False
    fd, info = opened
    with os.fdopen(fd, "rb") as src:
        target.parent.mkdir(parents=True, exist_ok=True)
        out = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        with os.fdopen(out, "wb") as dst:
            shutil.copyfileobj(src, dst, 1024 * 1024)
            dst.flush()
            if preserve_owner:
                os.fchown(dst.fileno(), info.st_uid, info.st_gid)
            os.fchmod(dst.fileno(), stat.S_IMODE(info.st_mode))
            os.utime(dst.fileno(), ns=(info.st_atime_ns, info.st_mtime_ns))
    return True


def apply_backup_scope(manifest, config):
    for scope in (config.get("backup_scope"), manifest.get("backup_scope")):
        if scope is not None and scope != HULY_RETIRED_SCOPE:
            raise RuntimeError("Unknown backup scope: " + str(scope))
    if (config.get("backup_scope") is not None or manifest.get("backup_scope") is not None):
        if manifest.get("backup_format") != "guest-files-v1":
            raise RuntimeError("Backup scope huly-retired-v1 requires guest-files-v1 format")
    if config.get("backup_scope") is not None:
        manifest["backup_scope"] = config["backup_scope"]


def verify_backup_scope(manifest, containers):
    scope = manifest.get("backup_scope")
    if scope is None:
        return
    if scope != HULY_RETIRED_SCOPE:
        raise RuntimeError("Unknown backup scope: " + str(scope))
    if manifest.get("backup_format") != "guest-files-v1":
        raise RuntimeError("Backup scope huly-retired-v1 requires guest-files-v1 format")
    for container in containers:
        name = container["_name"]
        project = (container["Config"].get("Labels") or {}).get("com.docker.compose.project")
        if (container["State"]["Running"] and
                (name.startswith(("huly_docker-", "onestack-huly-")) or project == "huly_docker")):
            raise RuntimeError("Retired Huly container is running: " + name)
    for item in manifest.get("database_exports", []):
        name = item.get("container", "")
        if name.startswith(("huly_docker-", "onestack-huly-")):
            raise RuntimeError("Retired Huly native export is present: " + name)

def clean(value):
    text = str(value)
    for secret in sorted(SECRETS, key=len, reverse=True):
        if len(secret) >= 6:
            text = text.replace(secret, "[REDACTED]")
    return text

def log(message):
    print(dt.datetime.now(dt.timezone.utc).isoformat() + " " + clean(message), flush=True)

def command(args, *, timeout=300, input=None, env=None):
    p = sp.run(args, input=input, capture_output=True, timeout=timeout, env=env)
    if p.returncode:
        raise RuntimeError(f"{args[0]} failed ({p.returncode}): " + clean(p.stderr.decode(errors="replace")[-1800:]))
    return p.stdout

def atomic_json(path, data):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)

def record_backup_issue(manifest):
    # Keep a failed attempt visible while its replacement is still running.
    atomic_json(STATE / "last-issue.json", {key: manifest[key] for key in
                ("run_id", "status", "started", "completed", "archive", "error") if key in manifest})

def check_staging_capacity(guest_specs):
    """Reserve room for the largest transient VM disk and selected-file stage."""
    estimate = 48 * 1024 ** 3
    success_path = STATE / "last-success.json"
    if success_path.exists():
        previous = json.loads(success_path.read_text())
        run_id = previous.get("run_id", "")
        if (previous.get("backup_format") == "guest-files-v1"
                and re.fullmatch(r"\d{4}-\d{2}-\d{2}t\d{6}z", run_id)):
            stage = STAGING / run_id
            if stage.is_dir() and not stage.is_symlink():
                allocated = int(command(["du", "-s", "-B1", str(stage)]).split()[0])
                estimate = max(estimate, int(allocated * 1.25))
    largest_snapshot = 0
    for name in guest_specs:
        xml = ET.fromstring(command(["virsh", "dumpxml", name]))
        disks = [disk for disk in xml.findall("./devices/disk") if disk.get("device") == "disk"]
        if len(disks) != 1 or disks[0].find("source") is None:
            raise RuntimeError("Cannot estimate VM snapshot size: " + name)
        source = disks[0].find("source").get("file")
        if not source:
            raise RuntimeError("VM disk is not a file: " + name)
        allocated = int(command(["du", "-s", "-B1", source]).split()[0])
        largest_snapshot = max(largest_snapshot, allocated)
    estimate += largest_snapshot
    usage = shutil.disk_usage(STAGING)
    reserve = max(20 * 1024 ** 3, int(usage.total * 0.15))
    if usage.free < estimate + reserve:
        raise RuntimeError("Insufficient staging headroom: a new backup needs approximately "
                           f"{estimate // 1024 ** 3} GiB plus {reserve // 1024 ** 3} GiB reserved for applications; "
                           f"{usage.free // 1024 ** 3} GiB available. Retained backups were not deleted.")
    log(f"Staging capacity checked: {usage.free // 1024 ** 3} GiB free; "
        f"{estimate // 1024 ** 3} GiB estimated plus {reserve // 1024 ** 3} GiB application reserve")

def inspect_containers():
    ids = command(["docker", "ps", "-aq"]).decode().split()
    data = json.loads(command(["docker", "inspect", *ids])) if ids else []
    for c in data:
        c["_name"] = c["Name"].lstrip("/")
        c["_env"] = dict(x.split("=", 1) for x in c["Config"].get("Env", []) if "=" in x)
        for key, value in c["_env"].items():
            if re.search("PASSWORD|PASSWD|SECRET|TOKEN|KEY", key):
                SECRETS.add(value)
    return [c for c in data if not c["_name"].startswith("onestack-twenty-migration")]

def stream_export(args, dest, compress=False, script=None):
    log("Exporting " + dest.name)
    with open(dest.with_suffix(dest.suffix + ".partial"), "wb") as raw:
        out = gzip.GzipFile(fileobj=raw, mode="wb", compresslevel=3) if compress else raw
        with sp.Popen(args, stdin=sp.PIPE if script else sp.DEVNULL, stdout=sp.PIPE, stderr=sp.PIPE) as p:
            if script:
                p.stdin.write(script.encode())
                p.stdin.close()
            try:
                shutil.copyfileobj(p.stdout, out, 1024 * 1024)
                error = p.stderr.read()
                rc = p.wait(timeout=60)
            finally:
                if compress:
                    out.close()
            if rc:
                raise RuntimeError("Export failed for " + dest.name + ": " + clean(error.decode(errors="replace")[-1200:]))
    partial = dest.with_suffix(dest.suffix + ".partial")
    if partial.stat().st_size < 32:
        raise RuntimeError("Export unexpectedly empty: " + dest.name)
    os.replace(partial, dest)

def http_json(container, path, method="GET", payload=None, port=7700):
    ip = next(n["IPAddress"] for n in container["NetworkSettings"]["Networks"].values() if n.get("IPAddress"))
    headers = {"Content-Type": "application/json"}
    key = container["_env"].get("MEILI_MASTER_KEY")
    if key:
        headers["Authorization"] = "Bearer " + key
    request = urllib.request.Request(f"http://{ip}:{port}{path}", method=method, headers=headers,
                                     data=json.dumps(payload).encode() if payload is not None else None)
    with urllib.request.urlopen(request, timeout=300) as r:
        return json.load(r)

def export_databases(containers, stage, manifest):
    stage.mkdir(parents=True, exist_ok=True)
    for c in containers:
        if not c["State"]["Running"]:
            continue
        name, env, image = c["_name"], c["_env"], c["Config"]["Image"]
        image = image.removeprefix("docker.io/").removeprefix("library/")
        dest = stage / name
        if "PG_MAJOR" in env or "postgres-spilo" in image:
            script = ('export PGPASSWORD="${POSTGRES_PASSWORD:-${PGPASSWORD_SUPERUSER:-}}"; '
                      'exec pg_dumpall -U "${POSTGRES_USER:-${PGUSER_SUPERUSER:-postgres}}" --clean --if-exists')
            stream_export(["docker", "exec", name, "sh", "-c", script], dest.with_suffix(".sql.gz"), True)
            manifest["database_exports"].append({"container": name, "type": "postgresql", "file": str(dest.with_suffix(".sql.gz"))})
        elif re.match(r"(?:mariadb|mysql)[:@]", image):
            script = ('export MYSQL_PWD="${MARIADB_ROOT_PASSWORD:-$MYSQL_ROOT_PASSWORD}"; '
                      'exec mariadb-dump -u root --all-databases --single-transaction --routines --events --triggers')
            stream_export(["docker", "exec", name, "sh", "-c", script], dest.with_suffix(".sql.gz"), True)
            manifest["database_exports"].append({"container": name, "type": "mariadb", "file": str(dest.with_suffix(".sql.gz"))})
        elif re.match(r"mongo[:@]", image):
            script = ('exec mongodump --username "$MONGO_INITDB_ROOT_USERNAME" '
                      '--password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --archive --gzip')
            stream_export(["docker", "exec", name, "sh", "-c", script], dest.with_suffix(".archive.gz"))
            manifest["database_exports"].append({"container": name, "type": "mongodb", "file": str(dest.with_suffix(".archive.gz"))})
        elif re.match(r"(?:redis|valkey/valkey)[:@]", image):
            remote = "/tmp/onestack-backup.rdb"
            # redis-cli --rdb waits for a complete replica snapshot, unlike a timed BGSAVE copy.
            script = ('if [ -n "$REDIS_PASSWORD" ]; then export REDISCLI_AUTH="$REDIS_PASSWORD"; '
                      'else unset REDISCLI_AUTH; fi; redis-cli --rdb ' + remote)
            command(["docker", "exec", name, "sh", "-c", script], timeout=600)
            command(["docker", "cp", name + ":" + remote, str(dest.with_suffix(".rdb"))])
            command(["docker", "exec", name, "rm", "-f", remote])
            # docker cp can deliver a container-planted symlink; never read through it.
            header = read_contained_header(dest.with_suffix(".rdb"), stage, 5)
            if header is None or header[0] != b"REDIS":
                raise RuntimeError("Invalid Redis snapshot: " + name)
            manifest["database_exports"].append({"container": name, "type": "redis", "file": str(dest.with_suffix(".rdb"))})
        elif re.search(r"cockroachdb/cockroach[:@]", image):
            uri = ("postgresql://root@localhost:26257/defaultdb?sslmode=verify-ca"
                   "&sslrootcert=/cockroach/certs/ca.crt&sslcert=/cockroach/certs/client.root.crt"
                   "&sslkey=/cockroach/certs/client.root.key")
            collection = "onestack-backups/" + manifest["run_id"]
            output = command(["docker", "exec", name, "cockroach", "sql", "--url=" + uri,
                              "--execute=BACKUP INTO 'nodelocal://1/" + collection + "';"], timeout=1800)
            if b"succeeded" not in output:
                raise RuntimeError("Cockroach backup did not report success")
            command(["docker", "cp", name + ":/cockroach/cockroach-data/extern/" + collection, str(dest)], timeout=600)
            manifest["database_exports"].append({"container": name, "type": "cockroach", "directory": str(dest)})
        elif "meilisearch" in image:
            task = http_json(c, "/dumps", "POST", {})
            deadline = time.monotonic() + 900
            while time.monotonic() < deadline:
                status = http_json(c, "/tasks/" + str(task["taskUid"]))
                if status["status"] == "succeeded":
                    break
                if status["status"] in ("failed", "canceled"):
                    raise RuntimeError("Meilisearch dump failed: " + name)
                time.sleep(2)
            else:
                raise RuntimeError("Meilisearch dump timed out")
            uid = status["details"]["dumpUid"]
            root = c["Config"].get("WorkingDir") or "/"
            source = root.rstrip("/") + "/dumps/" + uid + ".dump"
            command(["docker", "cp", name + ":" + source, str(dest.with_suffix(".dump"))], timeout=600)
            manifest["database_exports"].append({"container": name, "type": "meilisearch", "file": str(dest.with_suffix(".dump")), "native_file": source})
        elif re.match(r"(?:docker\.elastic\.co/elasticsearch/)?elasticsearch[:@]", image):
            repository = "onestack-backup"
            http_json(c, "/_snapshot/" + repository, "PUT",
                      {"type": "fs", "settings": {"location": "/snapshots", "compress": True}}, port=9200)
            snapshot = manifest["run_id"].lower()
            result = http_json(c, "/_snapshot/" + repository + "/" + snapshot + "?wait_for_completion=true",
                               "PUT", {"include_global_state": True}, port=9200)
            if result["snapshot"]["state"] != "SUCCESS":
                raise RuntimeError("Elasticsearch snapshot failed")
            manifest["database_exports"].append({"container": name, "type": "elasticsearch",
                                                "repository": "/var/backups/onestack/elasticsearch", "snapshot": snapshot})

def export_native_postgresql(stage, manifest):
    if not shutil.which("pg_lsclusters"):
        return
    for cluster in json.loads(command(["pg_lsclusters", "--json"])):
        if not cluster.get("running", cluster.get("status") == "online"):
            continue
        name = "host-postgresql-" + cluster["version"] + "-" + cluster["cluster"]
        dest = stage / (name + ".sql.gz")
        owner = cluster.get("owner") or pwd.getpwuid(cluster["owneruid"]).pw_name
        stream_export(["runuser", "-u", owner, "--", "pg_dumpall", "-p", str(cluster["port"]),
                       "--clean", "--if-exists"], dest, True)
        manifest["database_exports"].append({"container": name, "type": "postgresql-host", "file": str(dest),
                                            "data_directory": cluster.get("pgdata", cluster.get("pgdatadir"))})

def guest_relative_path(value):
    path = PurePosixPath(value)
    if not path.is_absolute() or path == PurePosixPath("/") or ".." in path.parts:
        raise ValueError("Guest backup path must be an absolute path below /: " + value)
    return Path(*path.parts[1:])


def guest_source(mountpoint, guest_path):
    """Return the real source for a guest path, refusing anything that leaves the guest.

    The guest filesystem is mounted on the host, so an absolute symlink inside it
    resolves against the host root. Following one would copy host files into the
    guest's backup as root.
    """
    relative = guest_relative_path(guest_path)
    source = Path(mountpoint) / relative
    if not os.path.lexists(source) or source.is_symlink():
        raise RuntimeError("Required guest path is missing or a symlink: " + guest_path)
    real = resolve_within(source, mountpoint)
    if real is None:
        raise RuntimeError("Guest path resolves outside the guest filesystem: " + guest_path)
    return real


def remove_guest_snapshot(image, mountpoint, guest_name, *, timeout_seconds=30):
    """Remove this run's disk copy only after detachment and job completion."""
    deadline = time.monotonic() + timeout_seconds
    size_path = Path("/sys/class/block/nbd0/size")
    while size_path.read_text().strip() != "0":
        if time.monotonic() >= deadline:
            raise RuntimeError(f"NBD /dev/nbd0 remains attached after {timeout_seconds}s")
        time.sleep(0.25)
    mount = sp.run(["mountpoint", "-q", str(mountpoint)], capture_output=True)
    if mount.returncode == 0:
        raise RuntimeError("Guest backup mountpoint remains mounted: " + str(mountpoint))
    if mount.returncode != 32:
        raise RuntimeError("Cannot verify guest backup mountpoint is unmounted: "
                           + str(mountpoint) + f" (mountpoint exit {mount.returncode})")
    state = command(["virsh", "domstate", guest_name]).decode().strip()
    if state != "shut off":
        job = command(["virsh", "domjobinfo", guest_name]).decode()
        if not re.search(r"Job type:\s+None", job):
            raise RuntimeError("Libvirt job is still active for guest " + guest_name)
    image.unlink()
    log("Removed temporary guest disk: " + str(image))


def copy_guest_paths(image, destination, spec, guest_name):
    """Copy selected paths from a completed VM snapshot, never its live disk."""
    mountpoint = Path("/run/onestack-backup/guest-root")
    mountpoint.mkdir(parents=True, exist_ok=True, mode=0o700)
    mountpoint.chmod(0o700)
    lock_path = Path("/run/onestack-backup/nbd.lock")
    with lock_path.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        command(["modprobe", "nbd", "max_part=8"])
        if (Path("/sys/class/block/nbd0/size").read_text().strip() != "0"
                or sp.run(["mountpoint", "-q", str(mountpoint)], capture_output=True).returncode == 0):
            message = ("Retained temporary guest disk " + str(image)
                       + ": backup NBD device or mountpoint is already in use")
            log(message)
            raise RuntimeError(message)
        connected = False
        mounted = False
        try:
            command(["qemu-img", "check", "-q", str(image)], timeout=600)
            command(["qemu-nbd", "--read-only", "--format=qcow2", "--connect=/dev/nbd0", str(image)])
            connected = True
            command(["udevadm", "settle"])
            fstype = command(["blkid", "-s", "TYPE", "-o", "value", "/dev/nbd0p1"]).decode().strip()
            if fstype != "ext4":
                raise RuntimeError("Unexpected guest root filesystem: " + fstype)
            command(["mount", "-t", "ext4", "-o", "ro,noload,nosuid,nodev,noexec", "/dev/nbd0p1", str(mountpoint)])
            mounted = True
            if not (mountpoint / "etc/os-release").is_file():
                raise RuntimeError("Guest root filesystem is missing /etc/os-release")
            rootfs = destination / "rootfs"
            rootfs.mkdir(parents=True, exist_ok=True)
            for guest_path in spec["paths"]:
                relative = guest_relative_path(guest_path)
                source = guest_source(mountpoint, guest_path)
                target = rootfs / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                # -a copies symlinks as links without following them. Guest device
                # nodes and FIFOs are not recreated on the host.
                args = ["rsync", "-aHAX", "--no-devices", "--no-specials", "--numeric-ids", "--one-file-system"]
                for pattern in spec.get("excludes", []):
                    args.extend(["--exclude", pattern])
                if source.is_dir():
                    target.mkdir(exist_ok=True)
                    args.extend([str(source) + "/", str(target) + "/"])
                else:
                    args.extend([str(source), str(target)])
                command(args, timeout=1800)
            for guest_path in spec["required"]:
                target = rootfs / guest_relative_path(guest_path)
                if not target.exists() and not target.is_symlink():
                    raise RuntimeError("Guest backup is missing a required restore path: " + guest_path)
        finally:
            try:
                if mounted:
                    # Keep the NBD attachment for manual recovery if unmount fails.
                    command(["umount", str(mountpoint)], timeout=60)
                if connected:
                    command(["qemu-nbd", "--disconnect", "/dev/nbd0"], timeout=60)
                remove_guest_snapshot(image, mountpoint, guest_name)
            except Exception as error:
                message = "Retained temporary guest disk " + str(image) + ": " + clean(error)
                log(message)
                raise RuntimeError(message) from error


def snapshot_guest_data(stage, manifest, guest_specs):
    present = set(command(["virsh", "list", "--all", "--name"]).decode().splitlines()) - {""}
    if present != set(guest_specs):
        raise RuntimeError("VM inventory differs from the reviewed guest backup scope")
    for name, spec in guest_specs.items():
        if not spec.get("paths") or not spec.get("required"):
            raise RuntimeError("Guest backup scope is incomplete: " + name)
        target = stage / name
        target.mkdir(parents=True, exist_ok=True)
        xml = command(["virsh", "dumpxml", name])
        (target / "domain.xml").write_bytes(xml)
        disks = ET.fromstring(xml).findall("./devices/disk")
        running = command(["virsh", "domstate", name]).decode().strip() == "running"
        backup = ET.Element("domainbackup", mode="push")
        diskset = ET.SubElement(backup, "disks")
        copies = []
        quiesced = False
        for disk in disks:
            source = disk.find("source")
            if source is None or not source.get("file"):
                continue
            original = Path(source.get("file"))
            if disk.get("device") != "disk":
                shutil.copy2(original, target / original.name)
                continue
            dev = disk.find("target").get("dev")
            if copies or dev != "vda":
                raise RuntimeError("Guest file backup expects one vda disk: " + name)
            scratch = Path("/var/lib/libvirt/images/onestack-backups") / (manifest["run_id"] + "-" + name + "-" + dev + ".qcow2")
            scratch.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
            if scratch.exists():
                raise RuntimeError("VM backup output already exists")
            if running:
                item = ET.SubElement(diskset, "disk", name=dev, type="file", backup="yes")
                ET.SubElement(item, "driver", type="qcow2")
                ET.SubElement(item, "target", file=str(scratch))
                copies.append(scratch)
            else:
                command(["cp", "--sparse=always", str(original), str(scratch)], timeout=1800)
                copies.append(scratch)
        if running and copies:
            backupxml = target / "backup.xml"
            ET.ElementTree(backup).write(backupxml)
            # Freeze only while libvirt establishes the snapshot point, then thaw
            # immediately while the independent backup job copies its data.
            try:
                command(["virsh", "domfsfreeze", name], timeout=20)
                quiesced = True
                command(["virsh", "backup-begin", name, "--backupxml", str(backupxml)], timeout=30)
            finally:
                # A timed-out freeze may still have succeeded in the guest.
                command(["virsh", "domfsthaw", name], timeout=20)
            deadline = time.monotonic() + 1800
            while time.monotonic() < deadline:
                result = command(["virsh", "domjobinfo", name]).decode()
                if re.search(r"Job type:\s+None", result):
                    break
                time.sleep(3)
            else:
                raise RuntimeError("VM backup timed out; inspect live libvirt job")
            completed = command(["virsh", "domjobinfo", name, "--completed", "--keep-completed"]).decode()
            if not re.search(r"Job type:\s+Completed", completed):
                raise RuntimeError("VM backup did not complete successfully")
        if len(copies) != 1:
            raise RuntimeError("Guest backup has no supported disk: " + name)
        scratch = copies[0]
        copy_guest_paths(scratch, target, spec, name)
        manifest["guest_exports"].append({"name": name, "directory": str(target),
                                          "format": "selected-rootfs-files-v1",
                                          "paths": spec["paths"], "required": spec["required"],
                                          "consistent_point_in_time": quiesced or not running,
                                          "guest_filesystems_quiesced": quiesced})

def backup_sqlite(source, destination, *, timeout_seconds=900, pages=1024):
    deadline = time.monotonic() + timeout_seconds
    def progress(status, remaining, total):
        if time.monotonic() > deadline:
            raise TimeoutError("SQLite backup exceeded its time limit: " + str(source))

    with closing(sqlite3.connect(source.as_uri() + "?mode=ro", uri=True, timeout=30)) as src:
        # Pin a WAL read snapshot so concurrent application writes cannot restart
        # the entire copy. WAL writers continue; closing src releases the reader.
        # Other journal modes retain incremental locking to avoid holding writers.
        if src.execute("PRAGMA journal_mode").fetchone()[0].lower() == "wal":
            src.execute("BEGIN")
            src.execute("SELECT rootpage FROM sqlite_master LIMIT 1").fetchone()
        with closing(sqlite3.connect(destination)) as dst:
            src.backup(dst, pages=pages, sleep=0.05, progress=progress)
            src.rollback()
            dst.set_progress_handler(lambda: int(time.monotonic() > deadline), 10000)
            if dst.execute("PRAGMA quick_check").fetchone()[0] != "ok":
                raise RuntimeError("SQLite snapshot check failed: " + str(source))


def sqlite_exclude_paths(config):
    return tuple(config.get("sqlite_exclude_paths", ())) + CIMS_EXCLUDED_DIRECTORIES


def sqlite_sidecars_safe(source):
    """SQLite opens -wal, -shm and -journal by name, and may write -shm even when
    reading. Refuse a database whose sidecar is anything but a regular file."""
    for suffix in ("-wal", "-shm", "-journal"):
        sidecar = Path(str(source) + suffix)
        try:
            if not stat.S_ISREG(os.lstat(sidecar).st_mode):
                return False
        except FileNotFoundError:
            continue
    return True


def snapshot_sqlite(containers, stage, manifest, exclude_paths=()):
    # Mount sources and their contents are writable by containers: walk without
    # following symlinks, and compare exclusions and containment on real paths.
    roots = {Path(m["Source"]) for c in containers for m in c.get("Mounts", [])
             if m.get("RW") and m.get("Type") in ("bind", "volume") and Path(m["Source"]).is_dir()}
    roots.update([Path("/root/.codex"), Path("/root/places_app")])
    excluded = tuple(os.path.realpath(value) for value in exclude_paths)
    seen = set()
    for root in sorted(roots):
        real_root = Path(os.path.realpath(root))
        if not real_root.is_dir() or within_any(real_root, excluded):
            continue
        for candidate in walk_files(real_root):
            if not candidate.name.endswith(SQLITE_SUFFIXES):
                continue
            source = resolve_within(candidate, real_root)
            if source is None or source in seen or within_any(source, excluded):
                continue
            header = read_contained_header(source, real_root, 16)
            if header is None or header[0] != SQLITE_HEADER:
                continue
            seen.add(source)
            metadata = header[1]
            if not sqlite_sidecars_safe(source):
                log("Skipping SQLite with a non-regular sidecar file: " + str(source))
                continue
            destination = stage / str(source).lstrip("/")
            destination.parent.mkdir(parents=True, exist_ok=True)
            started = time.monotonic()
            log("Snapshotting SQLite " + str(source))
            backup_sqlite(source, destination)
            current = read_contained_header(source, real_root, 0)
            if (current is None or (current[1].st_dev, current[1].st_ino) != (metadata.st_dev, metadata.st_ino)
                    or not sqlite_sidecars_safe(source)):
                destination.unlink(missing_ok=True)
                raise RuntimeError("SQLite source changed type or location during its snapshot: " + str(source))
            log("SQLite snapshot checked in " + str(round(time.monotonic() - started, 1)) + "s: " + str(source))
            os.chown(destination, metadata.st_uid, metadata.st_gid, follow_symlinks=False)
            os.chmod(destination, metadata.st_mode & 0o777)
            manifest["sqlite_exports"].append({"source": str(source), "snapshot": str(destination),
                                              "uid": metadata.st_uid, "gid": metadata.st_gid,
                                              "mode": oct(metadata.st_mode & 0o777)})

def snapshot_broker_files(containers, stage, manifest):
    """Flush Loki and briefly freeze mutable file stores for complete disk copies."""
    for c in containers:
        image = c["Config"]["Image"]
        loki = re.match(r"grafana/loki[:@]", image) is not None
        broker = re.search(r"redpandadata/redpanda[:@]", image) is not None
        if not c["State"]["Running"] or not (loki or broker):
            continue
        if c["State"].get("Paused"):
            raise RuntimeError("Broker was already paused; refusing to alter its state")
        name = c["_name"]
        if loki:
            ip = next(n["IPAddress"] for n in c["NetworkSettings"]["Networks"].values() if n.get("IPAddress"))
            request = urllib.request.Request(f"http://{ip}:3100/flush", method="POST", data=b"")
            with urllib.request.urlopen(request, timeout=300) as response:
                response.read()
        log("Taking a brief filesystem snapshot of " + name)
        try:
            command(["docker", "pause", name])
            for m in c["Mounts"]:
                expected = "/loki" if loki else "/var/lib/redpanda/data"
                if not m.get("RW") or m.get("Destination") != expected:
                    continue
                source = Path(m["Source"])
                destination = stage / name
                destination.mkdir(parents=True, exist_ok=True)
                command(["sync", "-f", str(source)])
                command(["cp", "-a", "--reflink=auto", str(source) + "/.", str(destination)], timeout=300)
                manifest.setdefault("filesystem_exports", []).append({"source": str(source), "snapshot": str(destination)})
        finally:
            current = json.loads(command(["docker", "inspect", name]))[0]
            if current["State"].get("Paused"):
                command(["docker", "unpause", name])

def preserve_postgres_configuration(containers, stage, manifest):
    """Use tested logical exports for live PG data, retaining cluster configuration."""
    exported = {x["container"] for x in manifest["database_exports"] if x["type"] == "postgresql"}
    manifest["raw_database_exclusions"] = [x["data_directory"] for x in manifest["database_exports"]
                                            if x.get("data_directory")]
    for c in containers:
        if c["_name"] not in exported:
            continue
        for mount in c["Mounts"]:
            if "postgres" not in mount["Destination"]:
                continue
            root = Path(mount["Source"])
            real_root = os.path.realpath(root)
            candidates = [root, root / "pgroot/data"]
            for data in candidates:
                # Container-writable: copy only regular files whose real path stays in the mount.
                real_data = resolve_within(data, real_root)
                if (real_data is None or not real_data.is_dir()
                        or read_contained_header(real_data / "PG_VERSION", real_root, 0) is None):
                    continue
                target = stage / c["_name"]
                target.mkdir(parents=True, exist_ok=True)
                copy_contained_file(real_data / "PG_VERSION", target / "PG_VERSION", real_root)
                for entry in sorted(os.scandir(real_data), key=lambda e: e.name):
                    if entry.name.endswith(".conf"):
                        copy_contained_file(Path(entry.path), target / entry.name, real_root)
                conf_d = real_data / "conf.d"
                if conf_d.is_dir() and not conf_d.is_symlink():
                    for source in walk_files(conf_d):
                        copy_contained_file(source, target / "conf.d" / source.relative_to(conf_d), real_root)
                manifest["raw_database_exclusions"].append(str(data))
    # Live database files are not independent backups. Use the completed native
    # exports and keep configuration files, rather than racing database writers.
    destinations = {"mariadb": {"/var/lib/mysql"}, "mongodb": {"/data/db", "/data/configdb"},
                    "redis": {"/data"}, "meilisearch": {"/meili_data"},
                    "cockroach": {"/cockroach/cockroach-data"},
                    "elasticsearch": {"/usr/share/elasticsearch/data"}}
    by_name = {c["_name"]: c for c in containers}
    for exported in manifest["database_exports"]:
        expected = destinations.get(exported["type"], set())
        for mount in by_name.get(exported["container"], {}).get("Mounts", []):
            if mount["Destination"] not in expected:
                continue
            source_root = Path(mount["Source"])
            real_root = Path(os.path.realpath(source_root))
            if real_root.is_dir():
                # Container-writable: never descend symlinks, read through them or chown through them.
                for source in walk_files(real_root):
                    if source.suffix in CONFIGURATION_SUFFIXES:
                        target = stage / exported["container"] / source.relative_to(real_root)
                        copy_contained_file(source, target, real_root, preserve_owner=True)
            manifest["raw_database_exclusions"].append(str(source_root))

def borg_create_command(config, manifest, archive, sources):
    """Build the archive command. Borg stores symlinks as links and is never given
    --read-special, so nothing outside the listed sources is read through a link."""
    cmd = ["borg", "create", "--stats", "--compression", "lz4", "--lock-wait", "60", archive, *sources]
    patterns = [*config.get("exclude", []), *CIMS_EXCLUDE_PATTERNS]
    for item in manifest["sqlite_exports"]:
        for suffix in ("", "-wal", "-shm"):
            patterns.append("pp:" + item["source"] + suffix)
    for item in manifest.get("filesystem_exports", []):
        patterns.append("pp:" + item["source"])
    for source in manifest.get("raw_database_exclusions", []):
        patterns.append("pp:" + source)
    for pattern in dict.fromkeys(patterns):
        cmd.extend(["--exclude", pattern])
    return cmd


def run_backup(args):
    os.umask(0o077)
    STATE.mkdir(parents=True, exist_ok=True)
    lock = open(STATE / "backup.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise RuntimeError("Another backup is running")
    config = json.loads(CONFIG.read_text())
    if not config.get("guest_backups"):
        raise RuntimeError("Guest backup scope is missing from configuration")
    if args.archive_exports:
        stage = Path(args.archive_exports).resolve()
        if stage.parent != STAGING or time.time() - stage.stat().st_mtime > 7200:
            raise RuntimeError("Export directory must be a fresh run under the configured staging path")
        manifest = json.loads((stage / "manifest.json").read_text())
        if manifest["status"] not in ("exports_complete", "warning"):
            raise RuntimeError("Only successfully completed exports may be archived")
        run_id = manifest["run_id"]
    else:
        run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dt%H%M%Sz")
        stage = STAGING / run_id
        stage.mkdir(parents=True, exist_ok=False)
        manifest = {"run_id": run_id, "started": dt.datetime.now(dt.timezone.utc).isoformat(),
                    "status": "running", "backup_format": "guest-files-v1",
                    "database_exports": [], "guest_exports": [], "sqlite_exports": []}
    apply_backup_scope(manifest, config)
    previous_path = STATE / "status.json"
    if previous_path.exists():
        previous = json.loads(previous_path.read_text())
        if previous.get("status") in ("warning", "failed"):
            record_backup_issue(previous)
    atomic_json(STATE / "status.json", manifest)
    try:
        if not args.archive_exports:
            check_staging_capacity(config["guest_backups"])
        containers = inspect_containers()
        verify_backup_scope(manifest, containers)
        atomic_json(stage / "containers.private.json", containers)
        manifest["containers"] = [{"name": c["_name"], "image": c["Config"]["Image"],
                                  "running": c["State"]["Running"]} for c in containers]
        if not args.archive_exports:
            export_databases(containers, stage / "databases", manifest)
            export_native_postgresql(stage / "databases", manifest)
            verify_backup_scope(manifest, containers)
            log("Database exports complete; capturing guest data from VM snapshots")
            snapshot_guest_data(stage / "guests", manifest, config["guest_backups"])
            log("Guest file checks passed; snapshotting SQLite databases")
            snapshot_sqlite(containers, stage / "sqlite", manifest, sqlite_exclude_paths(config))
        if not args.archive_exports or not manifest.get("filesystem_exports"):
            snapshot_broker_files(containers, stage / "filesystems", manifest)
        preserve_postgres_configuration(containers, stage / "postgres-configuration", manifest)
        sources = [p for p in config["sources"] if Path(p).exists()]
        sources.append(str(stage))
        if Path("/var/backups/onestack/elasticsearch").exists():
            sources.append("/var/backups/onestack/elasticsearch")
        manifest["sources"] = sources
        atomic_json(stage / "manifest.json", manifest)
        if args.exports_only:
            manifest["status"] = "exports_complete"
            atomic_json(stage / "manifest.json", manifest)
            atomic_json(STATE / "status.json", manifest)
            log("Exports complete: " + str(stage))
            return
        env = os.environ.copy()
        env.update(config["borg_environment"])
        suffix = "-retry-" + dt.datetime.now(dt.timezone.utc).strftime("%H%M%S") if manifest.get("archive") else ""
        archive = config["repository"] + "::onestack-" + run_id + suffix
        cmd = borg_create_command(config, manifest, archive, sources)
        log("Creating encrypted off-site archive " + archive.split("::", 1)[1])
        p = sp.run(cmd, env=env, capture_output=True, timeout=14400)
        log(p.stderr.decode(errors="replace")[-10000:])
        if p.returncode not in (0, 1):
            raise RuntimeError("Borg archive creation failed")
        manifest["archive"] = archive.split("::", 1)[1]
        manifest["borg_exit_code"] = p.returncode
        manifest["status"] = "success" if p.returncode == 0 else "warning"
        manifest["completed"] = dt.datetime.now(dt.timezone.utc).isoformat()
        atomic_json(stage / "manifest.json", manifest)
        atomic_json(STATE / "status.json", manifest)
        if p.returncode == 1:
            record_backup_issue(manifest)
        if p.returncode == 0:
            atomic_json(STATE / "last-success.json", manifest)
            import importlib.util
            spec = importlib.util.spec_from_file_location("native_cleanup", "/usr/local/libexec/onestack-native-backup-cleanup.py")
            cleaner = importlib.util.module_from_spec(spec); spec.loader.exec_module(cleaner)
            cleaner.cleanup(containers, manifest, http_json, command, atomic_json, log)
            # Remote retention is managed off-host; the VPS key is append-only.
            completed = []
            for previous in sorted(STAGING.iterdir()):
                manifest_path = previous / "manifest.json"
                if previous.is_dir() and manifest_path.exists():
                    old_manifest = json.loads(manifest_path.read_text())
                    if old_manifest.get("status") == "success":
                        completed.append(previous)
                    elif previous != stage:
                        shutil.rmtree(previous)
            for previous in completed[:-2]:
                shutil.rmtree(previous)
        log("Backup " + manifest["status"] + ": " + manifest["archive"])
        if p.returncode == 1:
            raise SystemExit(1)
    except Exception as e:
        manifest.update(status="failed", error=clean(e), completed=dt.datetime.now(dt.timezone.utc).isoformat())
        record_backup_issue(manifest)
        atomic_json(STATE / "status.json", manifest)
        atomic_json(stage / "manifest.json", manifest)
        sp.run(["logger", "-p", "daemon.err", "-t", "onestack-backup", clean(e)])
        raise

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--exports-only", action="store_true")
    parser.add_argument("--archive-exports")
    def interrupted(signum, frame):
        raise RuntimeError("Backup interrupted by signal " + str(signum))
    signal.signal(signal.SIGTERM, interrupted)
    try:
        run_backup(parser.parse_args())
    except Exception as error:
        log("FAILED: " + clean(error))
        sys.exit(2)
