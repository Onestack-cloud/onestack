# WCS CIMS data: Borg exclusion and purge plan, 7 October 2026

George approved "exclude and purge" on 7 October 2026. From now on, new Onestack Borg archives must not contain Women's Community Shelters (WCS) CIMS client data or credentials, and the copies already in the Hetzner Storage Box archives are to be removed once the runner has moved to George's hardware in Australia (targeted for Friday 9 October 2026).

Nothing in this document has been run against the VPS or the Storage Box. Every command below is for George to run himself, in order. Each step says what to check before moving on.

## What is excluded and why

The paths come from `cims-export-worker/docs/data-retention.md`, the runner's systemd units (`WorkingDirectory`, `EnvironmentFile` and log redirection) and the isolation drop-ins in `../systemd/cims-export-worker*.service.d/`. Those drop-ins set `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes` and `ReadWritePaths=/opt/cims-export-worker /var/lib/onestack-cims`, so the runner can only write in those two trees, in its private `/tmp` (never backed up) and to its log.

| Borg pattern | Covers |
| --- | --- |
| `sh:opt/cims-export-worker*` | The whole runner tree: `data/cims-export-worker.sqlite` and its `-wal`/`-shm` (CIMS session cookie and CSRF token during a run), `data/verification-code.txt` (emergency login code), any `CURATION_WORK_DIR` under it, `exports/` and `.dev.vars*` that the deploy rsync never deletes, and renamed copies such as `cims-export-worker.previous` |
| `sh:etc/cims-export-worker*` | `/etc/cims-export-worker/cims-export-worker.env`: CIMS username and password, export API token |
| `sh:var/lib/onestack-cims*` | The runner's `HOME`, the only other place its sandbox can write (and so the only other place `CURATION_WORK_DIR` can point) |
| `sh:var/log/cims-export-worker.log*` | The runner log and its logrotate copies |
| `sh:**/cims-export-worker/data` | Runner data in any other checkout, including staged copies of the Codex and CI guest files |
| `sh:**/cims-export-worker/exports` | D1 dumps and CSV exports in any checkout |
| `sh:**/cims-export-worker/.dev.vars*` | Worker secrets in any checkout |
| `sh:**/wcs-curate-*` | Curation folders from `tempfile.mkdtemp(prefix="wcs-curate-")` if `TMPDIR` ever points at a backed-up path |
| `sh:**/wcs-cims-*` | Working folders of the R2 download helpers (`wcs-cims-csv-zip`, `wcs-cims-latest-*`) |

Everything else stays in the backup, including the runner's systemd unit files, drop-ins and logrotate file, which hold no secrets. `/var/lib/onestack-cims` and `/var/log` are not current backup sources; their patterns are defensive.

`scripts/onestack-backup.py` now adds these patterns to every `borg create` even if the live `/etc/onestack-backup/config.json` lacks them, and its SQLite snapshot never reads the runner directories. Borg stores symlinks as links and is never given `--read-special`, so a link planted elsewhere cannot pull this data in. `tests/test_cims_backup_exclusions.py` runs the real Borg pattern engine against a disposable repository. It checks that every path above is dropped while every guest restore path and other sample file is kept, and that `recreate` plus `compact --threshold 0` physically removes the data.

## Before you start

### 1. Deploy the exclusion now (do not wait for the move)

From the merged `main` checkout on the laptop:

```sh
cd ~/workspace/onestack
scp infrastructure/hardening/scripts/onestack-backup.py onestack-admin:/root/onestack-backup.py.new
ssh onestack-admin 'python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" /root/onestack-backup.py.new \
  && cp -p /usr/local/libexec/onestack-backup.py /root/onestack-backup.py.pre-cims-exclusion \
  && install -o root -g root -m 0700 /root/onestack-backup.py.new /usr/local/libexec/onestack-backup.py \
  && rm /root/onestack-backup.py.new \
  && grep -c "sh:opt/cims-export-worker\*" /usr/local/libexec/onestack-backup.py'
```

The last command must print `1`. Optionally record the patterns in the live config too (the script enforces them either way):

```sh
ssh onestack-admin 'python3 - <<'"'"'EOF'"'"'
import json, os
path = "/etc/onestack-backup/config.json"
config = json.load(open(path))
patterns = ["sh:opt/cims-export-worker*", "sh:etc/cims-export-worker*", "sh:var/lib/onestack-cims*",
            "sh:var/log/cims-export-worker.log*", "sh:**/cims-export-worker/data",
            "sh:**/cims-export-worker/exports", "sh:**/cims-export-worker/.dev.vars*",
            "sh:**/wcs-curate-*", "sh:**/wcs-cims-*"]
config["exclude"] = config["exclude"] + [p for p in patterns if p not in config["exclude"]]
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(config, f, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, path)
print(len(config["exclude"]), "exclusions")
EOF'
```

This change also hardens how the backup handles container- and guest-controlled paths. The guest root is now mounted `ro,noload,nosuid,nodev,noexec`, rsync skips guest device nodes and FIFOs, and symlinks in Docker volumes and guest paths are no longer followed. Watch the next scheduled run (00:00 or 12:00 UTC):

```sh
ssh onestack-admin 'systemctl status onestack-backup.service --no-pager; tail -n 40 /var/log/borg/backup.log'
```

If it fails, restore the previous script with `ssh onestack-admin 'install -o root -g root -m 0700 /root/onestack-backup.py.pre-cims-exclusion /usr/local/libexec/onestack-backup.py'` and report the log line.

The runner keeps working until the move, but its local state (run metadata, which D1 also holds) is no longer backed up. That is the intended effect of the decision.

### 2. Confirm the move is complete

Run one manual release from the new host and confirm SharePoint and Power BI, then stop the Hetzner runner (see "Wipe the old VPS" below). Do not start the purge while the Hetzner runner is still active.

### 3. Set up a laptop shell with the deletion-capable credential

The purge must run from the laptop with the independent recovery credential in Keychain. **Never run it from the VPS:** the VPS key is append-only, so a purge through it would be recorded but never physically applied, and could be rolled back.

Use one shell for every step below (zsh or bash). Nothing here prints the passphrase or key.

```sh
umask 077
RET="$HOME/Library/Application Support/Onestack Recovery/retention"
WORK="$HOME/Library/Application Support/Onestack Recovery/cims-purge-2026-10"
mkdir -p "$WORK/list-before" "$WORK/list-after"
export BORG_REPO='ssh://u437236@u437236.your-storagebox.de:23/./backups/onestack_monolith'
export BORG_REMOTE_PATH=borg-1.4
export BORG_CACHE_DIR="$HOME/Library/Caches/onestack-borg"
export BORG_SECURITY_DIR="$HOME/Library/Application Support/Onestack Recovery/borg-security"
export TZ=UTC
export BORG_PASSCOMMAND="/opt/homebrew/bin/python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from keychain_recovery import read_bundle; print(read_bundle()[\"passphrase\"])' '$RET'"
KEYDIR="$(mktemp -d)"
KEY="$KEYDIR/storagebox"
/opt/homebrew/bin/python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from keychain_recovery import read_bundle; open(sys.argv[2], "w").write(read_bundle()["storagebox_ssh_private_key"])' "$RET" "$KEY"
chmod 600 "$KEY"
export BORG_RSH="ssh -4 -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=20 -o ServerAliveInterval=15 -o ServerAliveCountMax=3"
SBOX() { ssh -4 -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -p 23 u437236@u437236.your-storagebox.de "$@"; }
```

When finished (after step e), remove the key copy with `rm -rf "$KEYDIR"`.

### 4. Pause both writers

```sh
# Laptop retention controller: it pins archive IDs, which recreate changes.
launchctl bootout "gui/$(id -u)/com.digitalnachos.onestack-backup-retention"
test ! -e "$RET/pending-transaction.json" && echo "no pending retention transaction"

# VPS backup timer: wait until no backup is running.
ssh onestack-admin 'systemctl stop onestack-backup.timer; systemctl is-active onestack-backup.service'
```

The last command must print `inactive`. If it prints `active`, wait and rerun it. If `pending-transaction.json` exists, stop and reconcile it first, as the off-host retention README describes.

## (a) List the archives and find every copy (read-only)

```sh
borg info | grep -E '^Repository ID'
/opt/homebrew/bin/python3 -c 'import json,sys; print("Trusted ID:", json.load(open(sys.argv[1]))["repository_id"])' "$RET/trusted-inventory.json"

borg list --consider-checkpoints --format '{archive}{TAB}{time}{TAB}{id}{NL}' | tee "$WORK/archives-before.tsv"
cut -f1 "$WORK/archives-before.tsv" > "$WORK/names.txt"
wc -l < "$WORK/names.txt"
```

The two repository IDs must match. Expect about 26 archives: the recent full archives, 17 historical archives and five configuration checkpoints. Any name ending in `.checkpoint` or `.recreate` is an interrupted backup or recreate; it may also hold the data and is handled in steps (b) and (d).

List the CIMS paths in every archive:

```sh
while IFS= read -r a; do
  printf '== %s\n' "$a"
  borg list --format '{type} {size:>12} {path}{NL}' "::$a" \
    'sh:opt/cims-export-worker*' 'sh:etc/cims-export-worker*' 'sh:var/lib/onestack-cims*' \
    'sh:var/log/cims-export-worker.log*' 'sh:**/cims-export-worker/data' \
    'sh:**/cims-export-worker/exports' 'sh:**/cims-export-worker/.dev.vars*' \
    'sh:**/wcs-curate-*' 'sh:**/wcs-cims-*'
done < "$WORK/names.txt" | tee "$WORK/cims-paths-before.txt"
```

Expect `opt/cims-export-worker/data/...` and `etc/cims-export-worker/cims-export-worker.env` in most archives.

Then look for copies the patterns would miss. This saves each archive's full file list (names only, no contents), which takes a while:

```sh
while IFS= read -r a; do
  borg list --format '{type} {size:>12} {path}{NL}' "::$a" > "$WORK/list-before/$a.txt"
done < "$WORK/names.txt"

grep -i -E 'cims|wcs|curate|womens|shelter' "$WORK"/list-before/*.txt \
  | grep -v -E ' (opt/cims-export-worker|etc/cims-export-worker|var/lib/onestack-cims|var/log/cims-export-worker\.log)' \
  | grep -v -E '/cims-export-worker/(data|exports|\.dev\.vars)|/wcs-curate-|/wcs-cims-' \
  | tee "$WORK/uncovered-before.txt"

grep -E '\.(qcow2|img|raw)$' "$WORK"/list-before/*.txt | tee "$WORK/vm-images-before.txt"
```

Check both outputs before going on.

- **`uncovered-before.txt`**: expected entries are unit and configuration files, such as `etc/systemd/system/cims-export-worker*.service`, the `.service.d/20-isolation.conf` drop-ins, `etc/logrotate.d/cims-export-worker` and `usr/local/libexec/cims-deploy-ssh`, and the CI guest's `github-actions-runner_cims-export-worker-data/_data/.runner` (a GitHub runner registration). Source code in a checkout (for example `.../cims-export-worker/src/...`) is not client data. **Anything else that could hold client rows or credentials** (CSV, SQLite, `.sql`, `.env`, a WCS workspace copy) is not covered: stop, add a pattern to `CIMS_EXCLUDE_PATTERNS` and its test, redeploy, and add the same `--exclude` to the commands below.
- **`vm-images-before.txt`**: archives made before the 23 September guest-file format (`legacy-vm-v1`) hold whole Codex and CI runner VM disks. `recreate` removes files by path and cannot reach inside a disk image. If WCS data could be inside one (for example a Codex workspace clone of a WCS repository, or the CI runner's work folder for `cims-export-worker` or `wcs-pbi-reporting`), delete those whole archives instead (see "Alternative" below).

## (b) Remove the paths from every archive

Use exactly these nine patterns and nothing else. **Do not add the other exclusions from `config.json`**: they would strip data that historical archives keep on purpose, such as the July AllBids database copies.

### Dry run (changes nothing)

```sh
borg recreate --dry-run --list --filter x --lock-wait 600 \
  --exclude 'sh:opt/cims-export-worker*' \
  --exclude 'sh:etc/cims-export-worker*' \
  --exclude 'sh:var/lib/onestack-cims*' \
  --exclude 'sh:var/log/cims-export-worker.log*' \
  --exclude 'sh:**/cims-export-worker/data' \
  --exclude 'sh:**/cims-export-worker/exports' \
  --exclude 'sh:**/cims-export-worker/.dev.vars*' \
  --exclude 'sh:**/wcs-curate-*' \
  --exclude 'sh:**/wcs-cims-*' \
  2>&1 | tee "$WORK/recreate-dry-run.txt"

grep '^Processing' "$WORK/recreate-dry-run.txt" | wc -l
grep '^x ' "$WORK/recreate-dry-run.txt" | grep -v -E '^x (opt/cims-export-worker|etc/cims-export-worker|var/lib/onestack-cims|var/log/cims-export-worker\.log)|/cims-export-worker/(data|exports|\.dev\.vars)|/wcs-curate-|/wcs-cims-'
borg list --consider-checkpoints --format '{archive}{TAB}{time}{TAB}{id}{NL}' | diff - "$WORK/archives-before.tsv" && echo "dry run changed nothing"
```

The `Processing` count must equal the number of archives. The second command must print nothing; any line it prints is a path outside the CIMS data and must be investigated before the real run. The third must print `dry run changed nothing`.

### Real run, one archive first

Choose the oldest historical archive from `names.txt` as a canary and set `CANARY` to its exact name:

```sh
CANARY='<oldest historical archive name from names.txt>'
borg recreate --list --filter x --lock-wait 600 \
  --exclude 'sh:opt/cims-export-worker*' \
  --exclude 'sh:etc/cims-export-worker*' \
  --exclude 'sh:var/lib/onestack-cims*' \
  --exclude 'sh:var/log/cims-export-worker.log*' \
  --exclude 'sh:**/cims-export-worker/data' \
  --exclude 'sh:**/cims-export-worker/exports' \
  --exclude 'sh:**/cims-export-worker/.dev.vars*' \
  --exclude 'sh:**/wcs-curate-*' \
  --exclude 'sh:**/wcs-cims-*' \
  "::$CANARY" 2>&1 | tee "$WORK/recreate-canary.txt"

borg list --format '{type} {size:>12} {path}{NL}' "::$CANARY" > "$WORK/canary-after.txt"
diff "$WORK/list-before/$CANARY.txt" "$WORK/canary-after.txt" | grep '^>' ; echo "(nothing above means no path was added)"
diff "$WORK/list-before/$CANARY.txt" "$WORK/canary-after.txt" | grep '^<' | grep -v -E ' (opt/cims-export-worker|etc/cims-export-worker|var/lib/onestack-cims|var/log/cims-export-worker\.log)|/cims-export-worker/(data|exports|\.dev\.vars)|/wcs-curate-|/wcs-cims-'
```

The last command must print nothing: the only removed lines are CIMS paths.

### Real run, all archives

```sh
borg recreate --list --filter x --lock-wait 600 \
  --exclude 'sh:opt/cims-export-worker*' \
  --exclude 'sh:etc/cims-export-worker*' \
  --exclude 'sh:var/lib/onestack-cims*' \
  --exclude 'sh:var/log/cims-export-worker.log*' \
  --exclude 'sh:**/cims-export-worker/data' \
  --exclude 'sh:**/cims-export-worker/exports' \
  --exclude 'sh:**/cims-export-worker/.dev.vars*' \
  --exclude 'sh:**/wcs-curate-*' \
  --exclude 'sh:**/wcs-cims-*' \
  2>&1 | tee "$WORK/recreate.txt"
```

Recreate keeps each archive's name and time but gives it a new ID. Borg 1.4 also processes `.checkpoint` archives. If the run is interrupted, run the same command again. A leftover `<name>.recreate` archive is the half-built replacement: once the original `<name>` lists without CIMS paths, delete the leftover with `borg delete "::<name>.recreate"`.

## (c) Compact so the data is physically removed

`recreate` only drops references. The data stays in the repository's segment files until compaction rewrites them.

### Append-only and snapshots on the Storage Box

- Hetzner Storage Boxes have no append-only switch of their own. Append-only is a Borg feature, set either in the repository's config or per SSH key with `command="borg serve --append-only ..."` in the Storage Box's `.ssh/authorized_keys`. Here it is per key: the VPS key is append-only and the laptop recovery key is not. The 10 and 23 September cleanups compacted successfully with the laptop key, which shows the repository itself is not append-only.
- **So append-only does not need to be turned off, provided the laptop key is used.** It would have to be turned off, temporarily and only for the duration of the compaction, if the check below shows the laptop key's line carries `--append-only`, or if compaction reports nothing freed. Under append-only, `borg compact` exits successfully but frees nothing, and the old transactions (with the data) remain and can be rolled back. This was reproduced locally in `tests/test_cims_backup_exclusions.py`.
- `borg config` only works on local repositories, so the repository setting cannot be checked remotely. The "compaction freed" line below is the practical check.
- Storage Box snapshots pin the old segment files. They were retired on 10 September and must still be absent.

```sh
ssh-keygen -y -f "$KEY" | ssh-keygen -lf -
SBOX 'cat .ssh/authorized_keys'
SBOX 'ls -1 /home/.zfs/snapshot'
SBOX 'df -Pk /home' | tee "$WORK/df-before-compact.txt"
```

The line for the laptop key (match its fingerprint or comment) must not contain `--append-only`. The snapshot listing must be empty; if it is not, stop and delete those snapshots in the Hetzner console after compaction. At least 4 GiB must be free.

### Compact

```sh
borg compact --verbose --progress --threshold 0 --lock-wait 600 2>&1 | tee "$WORK/compact.txt"
grep 'compaction freed' "$WORK/compact.txt"
SBOX 'df -Pk /home' | tee "$WORK/df-after-compact.txt"
SBOX 'ls -1 /home/.zfs/snapshot'
```

**`--threshold 0` is essential.** By default Borg skips any segment where less than 10% is freeable. The CIMS files are small next to Borg's 500 MiB segments, so with the default most of the data would stay on disk; this was reproduced locally. With `0`, every segment holding deleted data is rewritten. That takes longer and briefly uses up to one segment of extra space at a time.

`grep 'compaction freed'` must print a line. If it prints nothing, the connection was append-only: stop, remove `--append-only` from the laptop key's line in `.ssh/authorized_keys` (leave the VPS key's line unchanged), rerun the compaction and then restore the line exactly as it was.

## (d) Verify the paths are gone

```sh
borg list --consider-checkpoints --format '{archive}{TAB}{time}{TAB}{id}{NL}' > "$WORK/archives-after.tsv"
diff <(cut -f1,2 "$WORK/archives-before.tsv") <(cut -f1,2 "$WORK/archives-after.tsv") && echo "same archive names and times"
grep -E '\.recreate' "$WORK/archives-after.tsv"

while IFS= read -r a; do
  borg list --format '{type} {size:>12} {path}{NL}' "::$a" \
    'sh:opt/cims-export-worker*' 'sh:etc/cims-export-worker*' 'sh:var/lib/onestack-cims*' \
    'sh:var/log/cims-export-worker.log*' 'sh:**/cims-export-worker/data' \
    'sh:**/cims-export-worker/exports' 'sh:**/cims-export-worker/.dev.vars*' \
    'sh:**/wcs-curate-*' 'sh:**/wcs-cims-*' | sed "s|^|$a: |"
done < "$WORK/names.txt" | tee "$WORK/cims-paths-after.txt"
wc -l < "$WORK/cims-paths-after.txt"

while IFS= read -r a; do
  borg list --format '{type} {size:>12} {path}{NL}' "::$a" > "$WORK/list-after/$a.txt"
done < "$WORK/names.txt"
grep -i -E 'cims|wcs|curate|womens|shelter' "$WORK"/list-after/*.txt | tee "$WORK/remaining-after.txt"

borg check --lock-wait 600 2>&1 | tee "$WORK/check.txt"
borg extract --stdout "::$(tail -n 1 "$WORK/names.txt")" etc/hostname
```

Expected results:

- `same archive names and times`, with no `.recreate` names.
- `cims-paths-after.txt` has `0` lines.
- `remaining-after.txt` holds only the unit and configuration files accepted in step (a).
- `borg check` ends without errors. It checks the repository and archive metadata and may take a long time; `--verify-data` is not needed for this.
- The sample extract prints the VPS host name. If the last name in `names.txt` is not a full `onestack-...` archive, use the newest one from `archives-after.tsv`.

## (e) Retention

### Re-baseline the laptop controller, then resume both writers

The controller refuses to run when a trusted archive's ID changes, and recreate changed them all. Record the new IDs only after confirming every trusted archive still exists with the same name and time:

```sh
test ! -e "$RET/pending-transaction.json"
cp -p "$RET/trusted-inventory.json" "$WORK/trusted-inventory.before-cims-purge.json"
borg list --json > "$WORK/list-after.json"
/opt/homebrew/bin/python3 - "$WORK/trusted-inventory.before-cims-purge.json" "$WORK/list-after.json" "$RET/trusted-inventory.json" <<'EOF'
import json, os, sys, time
old, new, out = (json.load(open(sys.argv[1])), json.load(open(sys.argv[2])), sys.argv[3])
assert new["repository"]["id"] == old["repository_id"], "repository identity changed"
times = {a["name"]: a["time"] for a in new["archives"]}
changed = [a["name"] for a in old["archives"] if times.get(a["name"]) != a["time"]]
assert not changed, "trusted archives missing or with a changed time: " + ", ".join(changed)
tmp = out + ".tmp"
with open(tmp, "w") as f:
    json.dump({"checked_at": time.time(), "repository_id": new["repository"]["id"],
               "archives": new["archives"], "reason": "WCS CIMS purge, borg recreate changed archive IDs"}, f, indent=2)
os.replace(tmp, out)
print("trusted inventory re-recorded:", len(new["archives"]), "archives")
EOF

ssh onestack-admin 'systemctl start onestack-backup.timer && systemctl list-timers onestack-backup.timer --no-pager'
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.digitalnachos.onestack-backup-retention.plist"
/opt/homebrew/bin/python3 "$RET/offhost-retention.py"
rm -rf "$KEYDIR"
```

The final command is the controller's dry run. It must finish without an error once a fresh full backup exists (it requires one under 18 hours old).

### Recommended policy

Today the trusted laptop controller keeps three daily full archives plus one weekly (`--glob-archives onestack-* --keep-daily 3 --keep-weekly 1`, approved on 10 September). The 17 historical archives and five configuration checkpoints are excluded from it and kept with no expiry. That is the part that accumulates indefinitely.

Recommendation:

1. **Full archives:** keep the approved policy and add `--keep-monthly 3`, so `POLICY` in `offhost-retention/offhost-retention.py` becomes `['--glob-archives', 'onestack-*', '--keep-daily', '3', '--keep-weekly', '1', '--keep-monthly', '3']`. That gives about three months of history and at most seven full archives.
2. **Historical archives and configuration checkpoints:** give them a 90-day expiry. Once the purge is verified, delete those older than 90 days and let the rest age out. The controller deliberately refuses to delete archives that do not match its full-archive name pattern, so these are removed by hand. For each name you decide to remove (from `names.txt`):

   ```sh
   borg delete --dry-run --list "::<historical archive name>"
   borg delete --list "::<historical archive name>"
   ```

   After the deletions, run `borg compact --verbose --threshold 0`, then re-record the trusted inventory with the script above.

Engineering constraints, not business choices: never fewer than three full recovery points, never the newest full archive, at least 4 GiB of Storage Box headroom, and the controller's checks stay in place.

**Business calls:**

- How much history Onestack keeps (the monthly count and the 90-day expiry for historical archives) is George's call as the Onestack operator, weighed against the retired Huly and Plane state those archives still hold and against any client contract terms.
- Whether any WCS data that cannot be removed by path (step a) may remain in a historical archive is WCS's call, through its privacy or data owner. The recommendation is that it may not.

## Alternative: delete archives or the whole repository

If `recreate` is impractical, there are two alternatives.

- **VM disk images found in step (a)**, recreate failing repeatedly, or the canary not checking out: delete the affected archives with `borg delete --list "::<name>"`, then run `borg compact --verbose --threshold 0` and re-record the trusted inventory. This loses those recovery points entirely.
- **Delete the whole repository:**

  ```sh
  borg delete --list "$BORG_REPO"
  ```

  This asks for confirmation. Then initialise a new repository with a new passphrase, store it in `/etc/onestack-backup/borg-passphrase` and the laptop Keychain bundle, record a new trusted inventory, and let the next backup upload in full.

Trade-off: deletion is the simplest guarantee and needs no path analysis. However, it discards every historical recovery point: the 8 and 27 September baselines, the retired Huly and Plane state and the configuration checkpoints. It also needs a new key and passphrase on both the VPS and the laptop. Until the first new archive completes there is no off-site backup at all, and that first full upload takes hours. `recreate` keeps everything except the CIMS data, at the cost of the checks above.

## Wipe the old VPS after the move

After the new host has produced a verified release, stop the Hetzner runner and delete its data. This can happen before or after the purge; the exclusion already keeps it out of new archives.

```sh
ssh onestack-admin 'systemctl disable --now cims-export-worker.service cims-export-worker-schedule.timer; systemctl stop cims-export-worker-schedule.service; systemctl is-active cims-export-worker.service'
ssh onestack-admin 'du -sh /opt/cims-export-worker/data /etc/cims-export-worker /var/lib/onestack-cims 2>/dev/null; ls -la /var/log/cims-export-worker.log* 2>/dev/null; find / -xdev \( -name "wcs-curate-*" -o -name "wcs-cims-*" -o -path "*/cims-export-worker/data" -o -path "*/cims-export-worker/exports" \) -print 2>/dev/null'
```

The first command must end with `inactive`. Review what the second lists. If it found anything outside the paths below, add it to the `rm` command. Then delete the runner's CIMS data directory, environment file, working folders and logs:

```sh
ssh onestack-admin 'rm -rf --one-file-system /opt/cims-export-worker/data /etc/cims-export-worker /var/lib/onestack-cims/* /var/log/cims-export-worker.log* && ls -la /opt/cims-export-worker /var/lib/onestack-cims'
```

Once the runner is retired for good, also remove `/opt/cims-export-worker`, the `onestack-cims` user, the `cims-deploy-ssh` key entry and the runner's unit files, and update `config/expected-services.example.json` and the live monitor inventory. These deletions are ordinary file deletions on an SSD-backed ext4 volume: they are not a forensic wipe. The remaining copies on the old disk disappear when Hetzner reprovisions the server.

Finally, update the "Borg backups" row in `cims-export-worker/docs/data-retention.md` to record the exclusion, the purge date and the verification result.
