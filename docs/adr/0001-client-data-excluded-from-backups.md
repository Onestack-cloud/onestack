# ADR-0001: Client data is excluded from backups by Borg-native patterns

- Status: Accepted
- Date: 2026-10-07
- Authors: George Vlachos

## Context

The VPS backup (`infrastructure/hardening/scripts/onestack-backup.py`) runs as root and sends Borg archives of `/opt`, `/etc`, `/root`, `/home`, Docker volumes and the guest VMs to a Hetzner Storage Box. A review on 7 October 2026 found that it had captured Women's Community Shelters (WCS) client records from the CIMS runner's working folders, along with the CIMS password file, session state and runner logs. It also found that the script followed symlinks planted in container-writable trees when copying Postgres and SQLite files, Redis dumps and guest paths. Script-side filtering was tried first, but the script's check and Borg's own path matching could disagree, so client data could still reach an archive.

## Decision

Client data and its credentials are excluded at the Borg level, using explicit `pp:` path-prefix and `sh:` patterns that the script always adds to every `borg create`, whatever the server's `config.json` says. The patterns cover the CIMS runner tree, its environment directory, its home, its logs and any staged copies of them. Any filtering in Python is defence in depth only. Python never follows symlinks or opens files by path under container-writable trees: it walks them through file descriptors with `O_NOFOLLOW`, checks that SQLite opened the files the walk found and fails the run if not.

## Consequences

What reaches an archive is decided by the same matcher Borg uses for `list` and `recreate`. That means tests against throwaway Borg repositories prove the exclusions, and the purge plan can reuse the same patterns. Any new service that holds client data must have its paths added to these patterns before it runs on the host. A database file replaced mid-run now fails the backup on purpose. Data inside whole VM disk images can't be excluded by path, so archives that contain such images have to be deleted whole. The purge plan is `infrastructure/hardening/reports/wcs-cims-backup-purge-2026-10-07.md`.

## Alternatives considered

- **Script-side filtering as the main control:** rejected, because the script and Borg can match paths differently and miss data silently.
- **Checking a path, then opening it:** rejected, because a container can swap the path for a symlink between the check and the open.
