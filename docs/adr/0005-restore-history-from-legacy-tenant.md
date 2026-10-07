# ADR-0005: Restore pre-cutover history by copying from the legacy tenant

- Status: Accepted
- Date: 2026-10-07
- Authors: George Vlachos

## Context

After the tenancy cutover (ADR-0002) the Usual Suspects dashboards started empty, because logs written before it sit in Loki's legacy `fake` tenant, which the proxy cannot read. Two ways to restore the last week were weighed. One was the existing backfill script, which re-reads Worker logs from Cloudflare's Workers Observability API. The other was a copy of what live ingest had already stored in the legacy tenant. The server holds no Cloudflare API credentials, Cloudflare may sample busy windows, and the legacy tenant holds the complete live data. However, ingest before the cutover wrote console arguments into `message` without redacting them, so the legacy lines cannot be copied as they are.

## Decision

History from before the cutover is restored by copying it from the legacy tenant with `scripts/copy-legacy-tenant-logs.mjs`, not by re-reading Cloudflare. The copy:

- copies only the named Worker scripts, whatever the selector returns;
- rebuilds console `message` fields from the original arguments and re-redacts every line with the shared redaction module (ADR-0004);
- writes under the `cloudflare-workers-backfill-full` source label, separate from live streams;
- skips entries the target already holds, matching the exact redacted line first and then timestamp and labels without `source`, so it can be re-run safely;
- paces pushes at about 1 MB with a pause and backs off on rate limits, so live ingestion keeps its share of Loki.

On 2026-10-07 it copied 155,960 entries covering 30 September to the cutover. Live ingestion was unaffected throughout.

## Consequences

The client got their recent history back from complete data with today's redaction, and no Cloudflare credential had to be handled. Only history younger than Loki's seven-day acceptance window could be restored; the legacy tenant's older week will age out unseen. Until about 21 October the admin dashboard, which reads every tenant, counts the copied week twice. Entries that became identical once redacted are stored once. The Observability backfill should not be run over the same window, because its entries carry different labels and would duplicate the copy.

## Alternatives considered

- **Cloudflare Workers Observability backfill.** It needs a Cloudflare API token on the server and returns data Cloudflare may have sampled. It remains the way to fill gaps that never reached Loki.
- **Copying legacy lines verbatim.** This was rejected because legacy console messages contain secrets that today's ingest would have redacted.
