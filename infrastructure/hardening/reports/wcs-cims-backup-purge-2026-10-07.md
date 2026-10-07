# WCS CIMS data: Borg exclusion and purge plan, 7 October 2026

George approved "exclude and purge" on 7 October 2026. From now on, new Onestack Borg archives must not contain Women's Community Shelters (WCS) CIMS client data or credentials. The copies already in the Hetzner Storage Box archives are to be removed once the runner has moved to George's hardware in Australia, targeted for Friday 9 October 2026.

Nothing in this document has been run against the VPS or the Storage Box. Every command below is for George to run himself, in order. Each step says what to check before moving on.

## What is excluded and why

The paths come from:

- `cims-export-worker/docs/data-retention.md`;
- the runner's systemd units (`WorkingDirectory`, `EnvironmentFile` and log redirection);
- the isolation drop-ins in `../systemd/cims-export-worker*.service.d/`.

Those drop-ins set `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes` and `ReadWritePaths=/opt/cims-export-worker /var/lib/onestack-cims`. So the runner can only write in those two trees, in its private `/tmp` (never backed up) and to its log. Step 1 checks this on the live host.

| Borg patterns | Covers |
| --- | --- |
| `pp:/opt/cims-export-worker`, `sh:**/opt/cims-export-worker*` | The runner tree, which includes:<br>• `data/cims-export-worker.sqlite` with its `-wal` and `-shm` (CIMS session cookie and CSRF token during a run);<br>• `data/verification-code.txt` (emergency login code);<br>• any `CURATION_WORK_DIR`;<br>• `exports/` and `.dev.vars*`, which the deploy rsync never deletes;<br>• renamed copies such as `cims-export-worker.previous`;<br>• copies of the tree that the backup itself stages under `/var/backups/onestack/runs` |
| `pp:/etc/cims-export-worker`, `sh:**/etc/cims-export-worker*` | `cims-export-worker.env`: CIMS username and password, export API token |
| `pp:/var/lib/onestack-cims`, `sh:**/var/lib/onestack-cims*` | The runner's `HOME`, the only other place its sandbox can write |
| `pp:/var/log/cims-export-worker.log`, `sh:**/var/log/cims-export-worker.log*` | The runner log and its logrotate copies |
| `sh:**/cims-export-worker/data*`, `sh:**/cims-export-worker/exports*`, `sh:**/cims-export-worker/.dev.vars*` | Data, D1 dumps, CSV exports and Worker secrets in any checkout, including near-miss names such as `data.bak` |
| `sh:**/wcs-curate-*`, `sh:**/wcs-cims-*` | Curation folders (`tempfile.mkdtemp(prefix="wcs-curate-")`) and the R2 download helpers' working folders |

Everything else stays in the backup, including the runner's systemd unit files, drop-ins and logrotate file, which hold no secrets. `/var/lib/onestack-cims` and `/var/log` are not current backup sources; their patterns are defensive.

These Borg patterns are the control that matters. `scripts/onestack-backup.py` passes them to every `borg create`, even if the live `/etc/onestack-backup/config.json` lacks them. Borg applies them to the literal paths it walks and never follows symlinks; the script never passes `--read-special`. The script's own skips of the runner directories are defence in depth only.

`tests/test_cims_backup_exclusions.py` runs the exact `borg create` command line the script builds against a disposable repository and proves that every path above is absent while every guest restore path is kept. It also runs this plan's own exclusion file through `borg recreate` and `borg compact --threshold 0` and confirms that the data is physically gone from the segment files.

## Before you start

### 1. Check the live runner, then deploy the exclusion (now, not after the move)

Confirm the live unit really is sandboxed. Then confirm the environment file does not move the data elsewhere; the `grep` prints key names only, never values:

```sh
ssh onestack-admin 'systemctl show cims-export-worker.service -p User -p ProtectSystem -p ReadWritePaths -p PrivateTmp'
ssh onestack-admin 'grep -o -E "^(CURATION_WORK_DIR|CIMS_DB_PATH|CIMS_VERIFICATION_CODE_FILE|TMPDIR)=" /etc/cims-export-worker/cims-export-worker.env'
```

Expect `User=onestack-cims`, `ProtectSystem=strict`, `ReadWritePaths=/opt/cims-export-worker /var/lib/onestack-cims` and `PrivateTmp=yes`. If any key is printed, look at where its value points. A location outside `/opt/cims-export-worker` and `/var/lib/onestack-cims` needs its own pattern (in `CIMS_EXCLUDE_PATTERNS`, its test and the exclusion file in step 3) before going further.

Deploy the script from the merged `main` checkout on the laptop:

```sh
cd ~/workspace/onestack
scp infrastructure/hardening/scripts/onestack-backup.py onestack-admin:/root/onestack-backup.py.new
ssh onestack-admin 'python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" /root/onestack-backup.py.new \
  && cp -p /usr/local/libexec/onestack-backup.py /root/onestack-backup.py.pre-cims-exclusion \
  && install -o root -g root -m 0700 /root/onestack-backup.py.new /usr/local/libexec/onestack-backup.py \
  && rm /root/onestack-backup.py.new \
  && grep -c "pp:/opt/cims-export-worker" /usr/local/libexec/onestack-backup.py'
```

The last command must print `1`. The live `config.json` needs no change, because the script enforces the patterns.

This change also hardens how the root backup handles container- and guest-controlled paths:

- container trees are walked and read through file descriptors;
- the guest root is mounted `ro,noload,nosuid,nodev,noexec`;
- rsync no longer recreates guest device nodes or FIFOs.

Watch the next scheduled run (00:00 or 12:00 UTC), or start one:

```sh
ssh onestack-admin 'systemctl start --no-block onestack-backup.service'
ssh onestack-admin 'systemctl is-active onestack-backup.service; tail -n 40 /var/log/borg/backup.log'
```

Repeat the second command until it prints `inactive` and the log ends with `Backup success`. If the run fails, restore the previous script and report the log line:

```sh
ssh onestack-admin 'install -o root -g root -m 0700 /root/onestack-backup.py.pre-cims-exclusion /usr/local/libexec/onestack-backup.py'
```

Until the move, the runner keeps working but its local state (run metadata, which D1 also holds) is no longer backed up. That is the intended effect of the decision.

### 2. Confirm the move is complete

Run one manual release from the new host and confirm SharePoint and Power BI. Then stop the Hetzner runner (see "Wipe the old VPS" below). Do not start the purge while the Hetzner runner is still active.

### 3. Set up a laptop shell with the deletion-capable credential

The purge must run from the laptop with the independent recovery credential in Keychain. **Never run it from the VPS.** The VPS key is append-only, so a purge through it is recorded but never physically applied, and can be rolled back.

Use one shell for every step below (zsh or bash). Nothing here prints the passphrase or key.

```sh
umask 077
RET="$HOME/Library/Application Support/Onestack Recovery/retention"
WORK="$HOME/Library/Application Support/Onestack Recovery/cims-purge-2026-10"
mkdir -p "$WORK/list-before" "$WORK/cims-before" "$WORK/list-after"
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

Write the exclusion file once and derive an include-only pattern file from it. Every later step uses these two files, so Borg's own matcher decides what counts as CIMS data:

```sh
cat > "$WORK/cims-excludes.txt" <<'EOF'
pp:/opt/cims-export-worker
pp:/etc/cims-export-worker
pp:/var/lib/onestack-cims
pp:/var/log/cims-export-worker.log
sh:**/opt/cims-export-worker*
sh:**/etc/cims-export-worker*
sh:**/var/lib/onestack-cims*
sh:**/var/log/cims-export-worker.log*
sh:**/cims-export-worker/data*
sh:**/cims-export-worker/exports*
sh:**/cims-export-worker/.dev.vars*
sh:**/wcs-curate-*
sh:**/wcs-cims-*
EOF
{ sed 's/^/+ /' "$WORK/cims-excludes.txt"; echo '- sh:**'; } > "$WORK/cims-only.patterns"
diff <(grep -o -E '"(pp|sh):[^"]+"' ~/workspace/onestack/infrastructure/hardening/scripts/onestack-backup.py | tr -d '"') "$WORK/cims-excludes.txt" && echo "matches the deployed script"
```

The last command must print `matches the deployed script`. When everything is finished (after step e), remove the key copy with `rm -rf "$KEYDIR"`.

### 4. Pause both writers

```sh
# Laptop retention controller: it pins archive IDs, which recreate changes.
launchctl bootout "gui/$(id -u)/com.digitalnachos.onestack-backup-retention"
test ! -e "$RET/pending-transaction.json" && echo "no pending retention transaction"

# VPS backup timer: wait until no backup is running.
ssh onestack-admin 'systemctl stop onestack-backup.timer; systemctl is-active onestack-backup.service'
```

The last command must print `inactive`; if it prints `active`, wait and rerun it. If `pending-transaction.json` exists, stop and reconcile it first, as the off-host retention README describes.

## (a) List the archives and find every copy (read-only)

```sh
borg info | grep -E '^Repository ID'
/opt/homebrew/bin/python3 -c 'import json,sys; print("Trusted ID:", json.load(open(sys.argv[1]))["repository_id"])' "$RET/trusted-inventory.json"

borg list --consider-checkpoints --format '{archive}{TAB}{time}{TAB}{id}{NL}' | tee "$WORK/archives-before.tsv"
cut -f1 "$WORK/archives-before.tsv" > "$WORK/names.txt"
wc -l < "$WORK/names.txt"
grep -E '\.(recreate|checkpoint)$' "$WORK/names.txt"
```

The two repository IDs must match. Expect about 26 archives: the recent full archives, 17 historical archives and five configuration checkpoints. A name ending in `.checkpoint` is an interrupted backup that may also hold the data; recreate processes it like any other. **A name ending in `.recreate` must be resolved before step (b)** (see "If recreate is interrupted").

List the CIMS paths and the full file list (names only, no contents) of every archive. This takes a while:

```sh
while IFS= read -r a; do
  borg list --format '{path}{NL}' --patterns-from "$WORK/cims-only.patterns" "::$a" > "$WORK/cims-before/$a.txt"
  borg list --format '{path}{NL}' "::$a" > "$WORK/list-before/$a.txt"
  printf '%6d CIMS paths  %s\n' "$(wc -l < "$WORK/cims-before/$a.txt")" "$a"
done < "$WORK/names.txt" | tee "$WORK/cims-counts-before.txt"
```

Expect `opt/cims-export-worker/data/...` and `etc/cims-export-worker/cims-export-worker.env` in most archives.

Then ask Borg which WCS-looking paths the patterns would **not** remove, and look for whole VM disk images:

```sh
while IFS= read -r a; do
  borg list --format '{path}{NL}' --exclude-from "$WORK/cims-excludes.txt" "::$a" \
    | grep -i -E 'cims|wcs|curate|womens|shelter' | sed "s|^|$a: |"
done < "$WORK/names.txt" | tee "$WORK/uncovered-before.txt"

grep -E '\.(qcow2|img|raw)$' "$WORK"/list-before/*.txt | tee "$WORK/vm-images-before.txt"
```

Check both outputs before going on.

- **`uncovered-before.txt`.** These entries are expected:
  - unit and configuration files: `etc/systemd/system/cims-export-worker*.service`, the `.service.d/20-isolation.conf` drop-ins, `etc/logrotate.d/cims-export-worker` and `usr/local/libexec/cims-deploy-ssh`;
  - the CI guest's `github-actions-runner_cims-export-worker-data/_data/.runner` (a GitHub runner registration);
  - source code in a checkout (for example `.../cims-export-worker/src/...`).

  **Anything else that could hold client rows or credentials** (CSV, SQLite, `.sql`, `.env`, a copy of a WCS workspace) is not covered. If you find any, stop and add a pattern to `CIMS_EXCLUDE_PATTERNS`, its test and `cims-excludes.txt`, redeploy, then start this step again.
- **`vm-images-before.txt`.** Archives made before the 23 September guest-file format (`legacy-vm-v1`) hold whole Codex and CI runner VM disks. `recreate` removes files by path and cannot reach inside a disk image. If WCS data could be inside one, delete those whole archives instead (see "Alternative" below). For example, it could be a Codex workspace clone of a WCS repository, or the CI runner's work folder for `cims-export-worker` or `wcs-pbi-reporting`.
- **Not detectable by path.** Codex session transcripts (`home/codex/.codex/sessions`, `root/.codex/sessions`) are backed up on purpose. If a Codex session on the VPS ever printed WCS client rows, those transcripts hold them, and no path pattern can tell. If that may have happened, decide whether to delete those sessions on the hosts and recreate with an extra pattern for them.

## (b) Remove the paths from every archive

Use only `cims-excludes.txt`. **Do not add the other exclusions from `config.json`.** They would strip data that historical archives keep on purpose, such as the July AllBids database copies.

### Dry run (changes nothing)

```sh
borg recreate --dry-run --list --filter x --lock-wait 600 \
  --exclude-from "$WORK/cims-excludes.txt" 2>&1 | tee "$WORK/recreate-dry-run.txt"

grep -c '^Processing' "$WORK/recreate-dry-run.txt"
diff <(sed -n 's/^x //p' "$WORK/recreate-dry-run.txt" | sort -u) <(cat "$WORK"/cims-before/*.txt | sort -u) \
  && echo "dry run removes exactly the CIMS paths"
borg list --consider-checkpoints --format '{archive}{TAB}{time}{TAB}{id}{NL}' | diff - "$WORK/archives-before.tsv" \
  && echo "dry run changed nothing"
```

Expected results:

- The `Processing` count equals the number of archives.
- The second command prints `dry run removes exactly the CIMS paths`. Any difference is a path outside the CIMS listing; investigate it before the real run.
- The third command prints `dry run changed nothing`.

### Real run, one archive first

Set `CANARY` to the exact name of the oldest historical archive in `names.txt`:

```sh
CANARY='<oldest historical archive name from names.txt>'
borg recreate --list --filter x --lock-wait 600 --exclude-from "$WORK/cims-excludes.txt" \
  "::$CANARY" 2>&1 | tee "$WORK/recreate-canary.txt"

borg list --format '{path}{NL}' "::$CANARY" > "$WORK/canary-after.txt"
comm -13 <(sort "$WORK/list-before/$CANARY.txt") <(sort "$WORK/canary-after.txt")
diff <(comm -23 <(sort "$WORK/list-before/$CANARY.txt") <(sort "$WORK/canary-after.txt")) \
     <(sort "$WORK/cims-before/$CANARY.txt") && echo "canary lost exactly the CIMS paths"
```

The `comm -13` line must print nothing, meaning no path was added. The last command must print `canary lost exactly the CIMS paths`.

### Real run, all archives

```sh
borg recreate --list --filter x --lock-wait 600 \
  --exclude-from "$WORK/cims-excludes.txt" 2>&1 | tee "$WORK/recreate.txt"
```

Recreate keeps each archive's name and time but gives it a new ID. Borg 1.4 also processes `.checkpoint` archives.

### If recreate is interrupted

Borg builds each replacement as `<name>.recreate` and only removes the original once the replacement is committed. A rerun cannot resume: it aborts when `<name>.recreate` already exists. So, before rerunning:

```sh
borg list --consider-checkpoints --format '{archive}{NL}' | grep '\.recreate$'
```

For each name printed, check the original:

```sh
borg list --format '{path}{NL}' --patterns-from "$WORK/cims-only.patterns" "::<name>"
```

- **If it still lists CIMS paths**, the replacement was not finished. Delete it:

  ```sh
  borg delete "::<name>.recreate"
  ```

- **If the original lists nothing**, the original was already replaced. Inspect the leftover before deleting it.

Then rerun the full command. It processes every archive again, which is harmless for those already clean.

## (c) Compact so the data is physically removed

`recreate` only drops references. The data stays in the repository's segment files until compaction rewrites them.

### Append-only and snapshots on the Storage Box

- **How append-only works here.** Hetzner Storage Boxes have no append-only switch of their own; append-only is a Borg feature. It is set either in the repository's config or per SSH key with `command="borg serve --append-only ..."` in the Storage Box's `.ssh/authorized_keys`. Here it is per key: the VPS key is append-only and the laptop recovery key is not. The 10 and 23 September cleanups compacted successfully with the laptop key, which shows the repository itself is not append-only.
- **So append-only does not need to be turned off, provided the laptop key is used.** It must be turned off, temporarily and only for the compaction, in two cases:
  - the check below shows the laptop key's line carries `--append-only`;
  - compaction reports nothing freed.
- **Why it matters.** Under append-only, `borg compact` exits successfully but frees nothing, and the old transactions (with the data) remain and can be rolled back. This was reproduced locally in `tests/test_cims_backup_exclusions.py`.
- **How to check it.** `borg config` only works on local repositories, so the repository setting cannot be checked remotely. The "compaction freed" line below is the practical check.
- **Snapshots.** Storage Box snapshots pin the old segment files. They were retired on 10 September and must still be absent.

```sh
ssh-keygen -y -f "$KEY" | ssh-keygen -lf -
SBOX 'cat .ssh/authorized_keys'
SBOX 'ls -1 /home/.zfs/snapshot'
SBOX 'df -Pk /home' | tee "$WORK/df-before-compact.txt"
```

Expected results:

- The line for the laptop key (match its fingerprint or comment) must not contain `--append-only`.
- The snapshot listing must be empty. If it is not, stop, and delete those snapshots in the Hetzner console after compaction.
- At least 4 GiB must be free.

### Compact

```sh
borg compact --verbose --progress --threshold 0 --lock-wait 600 2>&1 | tee "$WORK/compact.txt"
grep 'compaction freed' "$WORK/compact.txt"
SBOX 'df -Pk /home' | tee "$WORK/df-after-compact.txt"
SBOX 'ls -1 /home/.zfs/snapshot'
```

**`--threshold 0` is essential.** By default Borg skips any segment where less than 10% is freeable. The CIMS files are small next to Borg's 500 MiB segments, so with the default most of the data would stay on disk; this was reproduced locally. With `0`, every segment holding deleted data is rewritten. That takes longer and briefly uses up to one segment of extra space at a time.

`grep 'compaction freed'` must print a line. If it prints nothing, the connection was append-only:

1. Stop.
2. Remove `--append-only` from the laptop key's line in `.ssh/authorized_keys`, leaving the VPS key's line unchanged.
3. Rerun the compaction.
4. Restore the line exactly as it was.

## (d) Verify the paths are gone

```sh
borg list --consider-checkpoints --format '{archive}{TAB}{time}{TAB}{id}{NL}' > "$WORK/archives-after.tsv"
diff <(cut -f1,2 "$WORK/archives-before.tsv") <(cut -f1,2 "$WORK/archives-after.tsv") && echo "same archive names and times"
grep '\.recreate' "$WORK/archives-after.tsv"

while IFS= read -r a; do
  borg list --format '{path}{NL}' --patterns-from "$WORK/cims-only.patterns" "::$a" | sed "s|^|$a: |"
done < "$WORK/names.txt" | tee "$WORK/cims-paths-after.txt"
wc -l < "$WORK/cims-paths-after.txt"

while IFS= read -r a; do
  borg list --format '{path}{NL}' "::$a" | grep -i -E 'cims|wcs|curate|womens|shelter' | sed "s|^|$a: |"
done < "$WORK/names.txt" | tee "$WORK/remaining-after.txt"

borg check --lock-wait 600 2>&1 | tee "$WORK/check.txt"
borg extract --stdout "::$(grep -E '^onestack-[0-9]{4}-' "$WORK/names.txt" | tail -n 1)" etc/hostname
```

Expected results:

- `same archive names and times`, and no `.recreate` names.
- `cims-paths-after.txt` has `0` lines.
- `remaining-after.txt` holds only the entries accepted in step (a).
- `borg check` ends without errors. It checks the repository and archive metadata and may take a long time; `--verify-data` is not needed for this.
- The sample extract from the newest full archive prints the VPS host name.

## (e) Retention

### Re-record the trusted inventory, then resume both writers in order

The laptop controller refuses to run when a trusted archive's ID changes, and recreate changed them all. The script below re-records the IDs only after confirming two things:

- the repository is the same;
- every trusted archive still exists with the same name and time, apart from archives you deliberately deleted.

If you deleted archives (here or under "Alternative"), first list their exact names, one per line, in `$WORK/deleted-archives.txt`. Otherwise leave the file empty:

```sh
touch "$WORK/deleted-archives.txt"
test ! -e "$RET/pending-transaction.json"
cp -p "$RET/trusted-inventory.json" "$WORK/trusted-inventory.before-cims-purge.json"
borg list --json > "$WORK/list-after.json"
/opt/homebrew/bin/python3 - "$WORK/trusted-inventory.before-cims-purge.json" "$WORK/list-after.json" \
    "$WORK/deleted-archives.txt" "$RET/trusted-inventory.json" <<'EOF'
import json, os, sys, time
old, new = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
deleted = {line.strip() for line in open(sys.argv[3]) if line.strip()}
out = sys.argv[4]
assert new["repository"]["id"] == old["repository_id"], "repository identity changed"
times = {a["name"]: a["time"] for a in new["archives"]}
missing = {a["name"] for a in old["archives"] if a["name"] not in times}
changed = [a["name"] for a in old["archives"] if a["name"] in times and times[a["name"]] != a["time"]]
assert not changed, "trusted archives with a changed time: " + ", ".join(sorted(changed))
assert missing <= deleted, "trusted archives missing but not listed as deleted: " + ", ".join(sorted(missing - deleted))
tmp = out + ".tmp"
with open(tmp, "w") as f:
    json.dump({"checked_at": time.time(), "repository_id": new["repository"]["id"], "archives": new["archives"],
               "reason": "WCS CIMS purge: borg recreate changed archive IDs",
               "deleted": sorted(missing)}, f, indent=2)
os.replace(tmp, out)
print("trusted inventory re-recorded:", len(new["archives"]), "archives;", len(missing), "deleted")
EOF
```

Resume the VPS writer and take a fresh full backup first. The controller needs a full archive under 18 hours old, and its LaunchAgent starts an applying run as soon as it is loaded:

```sh
ssh onestack-admin 'systemctl start onestack-backup.timer && systemctl start --no-block onestack-backup.service'
ssh onestack-admin 'systemctl is-active onestack-backup.service; tail -n 3 /var/log/borg/backup.log'
```

Repeat the second command until it prints `inactive` and `Backup success`. Then run the controller's dry run by hand. It must print a JSON receipt with `"applied": false`; an empty output means another run held its lock, so rerun it. Load the LaunchAgent last:

```sh
/opt/homebrew/bin/python3 "$RET/offhost-retention.py"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.digitalnachos.onestack-backup-retention.plist"
rm -rf "$KEYDIR"
```

### Recommended policy

The laptop controller keeps three daily full archives plus one weekly: `--glob-archives onestack-* --keep-daily 3 --keep-weekly 1`, approved on 10 September. The 17 historical archives and five configuration checkpoints are outside that policy and kept with no expiry. That is the part that accumulates indefinitely.

Recommendation:

1. **Full archives.** Keep the approved policy and add `--keep-monthly 3`, so that `POLICY` in `offhost-retention/offhost-retention.py` becomes:

   ```python
   ['--glob-archives', 'onestack-*', '--keep-daily', '3', '--keep-weekly', '1', '--keep-monthly', '3']
   ```

   That gives about three months of history and at most seven full archives.
2. **Historical archives and configuration checkpoints.** Give them a 90-day expiry: once the purge is verified, delete those older than 90 days and let the rest age out. The controller deliberately refuses to delete archives that do not match its full-archive name pattern, so these are removed by hand. For each name you decide to remove (from `names.txt`):

   ```sh
   borg delete --dry-run --list "::<historical archive name>"
   borg delete --list "::<historical archive name>"
   echo '<historical archive name>' >> "$WORK/deleted-archives.txt"
   ```

   Then run `borg compact --verbose --threshold 0` and re-record the trusted inventory with the script above.

**Engineering constraints (not business choices).** Never keep fewer than three full recovery points, never delete the newest full archive, keep at least 4 GiB of Storage Box headroom and leave the controller's checks in place.

**Business calls.**

- How much history Onestack keeps (the monthly count and the 90-day expiry for historical archives) is George's call as the Onestack operator. He should weigh it against the retired Huly and Plane state those archives still hold and any client contract terms.
- Whether any WCS data that cannot be removed by path (step a) may remain in a historical archive is WCS's call, through its privacy or data owner. The recommendation is that it may not.

## Alternative: delete archives or the whole repository

If `recreate` is impractical, there are two alternatives.

- **Delete the affected archives.** Use this for VM disk images found in step (a), when recreate fails repeatedly or when the canary does not check out:
  1. Add each name to `deleted-archives.txt`.
  2. Run `borg delete --list "::<name>"`.
  3. Run `borg compact --verbose --threshold 0`.
  4. Re-record the trusted inventory.

  This loses those recovery points entirely.
- **Delete the whole repository.** `borg delete --list "$BORG_REPO"` asks for confirmation. Then:
  1. Initialise a new repository with a new passphrase.
  2. Store the passphrase in `/etc/onestack-backup/borg-passphrase` and in the laptop Keychain bundle.
  3. Let the next backup upload in full.
  4. Write a fresh `trusted-inventory.json` from `borg list --json`. The script above refuses a new repository on purpose, so record the new repository ID and archives by hand after checking the first archive.

The trade-off is simplicity against history:

- **Deletion** is the simplest guarantee and needs no path analysis. However, it discards every historical recovery point: the 8 and 27 September baselines, the retired Huly and Plane state and the configuration checkpoints. It also needs a new key and passphrase on both the VPS and the laptop. Until the first new archive completes there is no off-site backup at all, and that upload takes hours.
- **Recreate** keeps everything except the CIMS data, at the cost of the checks above.

## Wipe the old VPS after the move

After the new host has produced a verified release, stop the Hetzner runner and delete its data. This can happen before or after the purge, because the exclusion already keeps it out of new archives.

```sh
ssh onestack-admin 'systemctl disable --now cims-export-worker.service cims-export-worker-schedule.timer; systemctl stop cims-export-worker-schedule.service; systemctl is-active cims-export-worker.service'
ssh onestack-admin 'du -sh /opt/cims-export-worker* /etc/cims-export-worker* /var/lib/onestack-cims 2>/dev/null; ls -la /var/log/cims-export-worker.log* 2>/dev/null; find / -xdev \( -path "/opt/cims-export-worker*" -prune -o -name "wcs-curate-*" -o -name "wcs-cims-*" -o -name ".dev.vars*" -o -path "*/cims-export-worker/data*" -o -path "*/cims-export-worker/exports*" -o -path "*/etc/cims-export-worker*" \) -print 2>/dev/null'
```

The first command must end with `inactive`. Review what the second lists, including anything under `/var/backups/onestack/runs`. If anything is outside the paths below, add it to the `rm` command.

Then delete the runner's CIMS data directory, the rest of its tree (including `exports/`, `.dev.vars*`, any working folders and renamed copies), the environment file, its home directory contents (including dotfiles) and its logs:

```sh
ssh onestack-admin 'rm -rf --one-file-system /opt/cims-export-worker/data /opt/cims-export-worker /opt/cims-export-worker.* /etc/cims-export-worker /etc/cims-export-worker.* /var/log/cims-export-worker.log* \
  && find /var/lib/onestack-cims -mindepth 1 -delete \
  && ls -la /opt | grep -i cims; ls -A /var/lib/onestack-cims'
```

Once the runner is retired for good, also remove:

- the `onestack-cims` user;
- the `cims-deploy-ssh` key entry;
- the runner's unit files and drop-ins.

Update `config/expected-services.example.json` and the live monitor inventory to match. These deletions are ordinary file deletions on an SSD-backed ext4 volume, not a forensic wipe. The remaining blocks on the old disk disappear when Hetzner reprovisions the server.

Finally, update the "Borg backups" row in `cims-export-worker/docs/data-retention.md` to record the exclusion, the purge date and the verification result.
