# ADR-0002: Loki tenancy, not query validation, isolates Usual Suspects logs

- Status: Accepted
- Date: 2026-10-07
- Authors: George Vlachos

## Context

The `usual-suspects-api` proxy in `onestack_products/cloudflare_logs_docker` gives the Usual Suspects Grafana org access to its own Cloudflare Worker logs in a shared Loki. It restricted access by scanning the LogQL text by hand and requiring every stream selector to contain the base labels. A security review showed this was bypassable: backtick strings desynchronised the quote tracking, substring matching accepted selectors with extra matchers and crafted quoting hid a second selector. Integration tests against the pinned Loki image confirmed that other services' logs leaked through the proxy. Any check that parses query text has to track Loki's full grammar to stay correct, so it is a weak place for an authorisation boundary.

## Decision

Isolation is enforced by Loki multi-tenancy. Loki runs with `auth_enabled: true`, and the proxy always sends `X-Scope-OrgID: usual-suspects` (`LOKI_TENANT`), never forwards caller headers and does not inspect query text for access control. Writers place logs by tenant:

- The ingest adapter and the backfill script route each Worker by exact script name through `LOKI_TENANT_BY_SCRIPT` (`script=tenant,...`).
- Scripts without a route go to `LOKI_DEFAULT_TENANT` (`cloudflare-workers`), which must not be a routed tenant, so unknown or look-alike scripts can never land in a restricted tenant.
- Services reject tenant IDs at startup that contain `|` (which Loki treats as a multi-tenant list) or that are `.` or `..`.
- Before every query the proxy checks that Loki answers a tenantless read with 401 "no org id", and returns 503 otherwise, so a Loki still running without tenancy fails closed.
- The admin Grafana datasource reads several tenants at once with `multi_tenant_queries_enabled`.

## Consequences

Any LogQL sent through the proxy, however crafted, can only read the `usual-suspects` tenant, and the proxy no longer needs to understand LogQL. Every new log writer must set `X-Scope-OrgID`, and adding a Worker to a restricted tenant means adding an exact route in both `docker-compose.yml` and the backfill defaults, which can drift. Logs written before the cutover stay in Loki's legacy `fake` tenant: admins see them until the 14-day retention expires them, but the Usual Suspects view starts at the cutover unless the window is re-backfilled. A deploy must recreate Loki and Grafana (`docker compose up -d --build --force-recreate`), because a bind-mounted config change alone does not restart them. The proxy adds one cheap probe request to Loki per query. Isolation of the Usual Suspects Grafana user from the admin org still depends on Grafana RBAC and is tracked separately.

## Alternatives considered

- **Parse queries with Loki's own parser (`/loki/api/v1/format_query`) and walk the AST.** This is stronger than hand-scanning, but it still makes query inspection the security boundary and depends on getting the AST checks right for every expression type Loki adds.
- **Strict character and operator allowlist with canonicalised selectors.** This would also close the known bypasses, but it limits the LogQL dashboards can use and stays a parser-differential risk, whereas tenancy makes the query text irrelevant to access.
