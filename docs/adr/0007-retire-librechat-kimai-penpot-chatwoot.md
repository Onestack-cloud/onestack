# ADR-0007: Retire LibreChat, Kimai, Penpot and Chatwoot

- Status: Accepted
- Date: 2026-10-07
- Authors: George Vlachos

## Context

After Twenty was retired (ADR-0006), a usage check covered every remaining service on the production host. Four were clearly unused. LibreChat's last conversation was in July 2025, Kimai's last sign-in in November 2025 and its last timesheet in October 2025, Penpot's last file change in April 2025, and Chatwoot had six messages in total, the newest from July 2024. Penpot and Chatwoot had been paused since August. LibreChat ran five containers, including a MongoDB server that held nothing else. Kimai, Penpot and Chatwoot were still offered in the Onestack app's catalogue and provisioned by its member code, and every page of the app loaded a Chatwoot chat widget from the stopped service. The same check found the host's backups had failed since 29 September for lack of disk space, which this cleanup helped resolve.

## Decision

LibreChat (with its RAG API, vector database, Meilisearch and the MongoDB server), Kimai, Penpot and Chatwoot are retired rather than kept, paused or updated. On 7 October 2026 their containers, volumes, network, images, databases and monitor entries were removed from the host after per-service backups were taken. Their catalogue rows were removed from the production app. In the codebase their Compose stacks, Ansible pieces and provisioning code were deleted, along with the Chatwoot widget. The app now skips retired products (Chatwoot, Kimai, LibreChat, Penpot, Plane and Twenty) when it provisions or removes members or changes passwords, rather than failing, because teams created earlier still list them.

## Consequences

The host expects 27 containers, and the backup coverage contract requires seven native database identities instead of ten. The off-host retention check, its test and the hardening README were updated to match. Password changes no longer fail for members of teams that list Plane. Archives in `/root/backups/apps-retired-20261007-095516` allow restoring any of these services' data. The DNS records for their hostnames and the Matrix and Plane catalogue entries, which also have no running service, were left for a separate decision. The standalone `meilisearch` service is in use and was kept.

## Alternatives considered

- **Keep the paused services paused.** Paused services still had to be backed up, patched and accounted for, and the app went on offering them to new teams.
