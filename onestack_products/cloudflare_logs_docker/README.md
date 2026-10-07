# Cloudflare Worker logs

Self-hosted Cloudflare Workers log viewer for `usual-suspects`.

## Architecture

Cloudflare Workers Logpush sends `workers_trace_events` to:

```text
https://logs.onestack.cloud/cloudflare-logpush
```

Traefik routes that path to the ingest adapter. The adapter validates the
`Authorization: Bearer ...` header, redacts sensitive keys, filters allowed
Worker script names, and writes to Loki. Grafana is exposed on the same host.

## Deploy

Create `.env` from `.env.example`, then run:

```bash
docker compose config
docker compose up -d --build
```

## Cloudflare Logpush destination

Use an HTTP destination with the bearer token as a request header:

```text
https://logs.onestack.cloud/cloudflare-logpush?header_Authorization=Bearer%20<token>
```

Use the `workers_trace_events` dataset and filter `ScriptName` to the allowed
Worker script names.

## Manual backfill

Historical Workers Logs can be backfilled from Cloudflare Workers Observability
while Cloudflare still retains them. Run the helper on the VPS from a container
that shares the ingest service network:

```bash
docker run --rm --network container:cloudflare-logs-ingest \
  -v /root/cloudflare_logs_docker/scripts:/scripts:ro \
  -e CF_API_EMAIL -e CF_API_KEY -e CF_ACCOUNT_ID \
  cloudflare_logs_docker-ingest \
  node /scripts/backfill-workers-observability.mjs \
    --source-label cloudflare-workers-backfill-full \
    --from "2026-06-02T00:00:00.000Z" \
    --to "2026-06-09T04:18:00.000Z" \
    --limit 2000
```

Use short windows, such as one hour, to avoid Cloudflare adaptive sampling. The
Grafana dashboard includes `cloudflare-workers` and
`cloudflare-workers-backfill-full` by default.
