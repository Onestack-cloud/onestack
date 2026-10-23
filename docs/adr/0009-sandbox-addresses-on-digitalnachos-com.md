# ADR-0009: Sandbox addresses live on digitalnachos.com, not digitalnachos.com.au

- Status: Accepted
- Date: 2026-10-23
- Authors: George Vlachos

## Context

Open-Inspect's self-hosted E2B sandboxes are reached at `https://<port>-<sandbox id>.<E2B_SANDBOX_DOMAIN>`, served by the `open-inspect-sandbox` Cloudflare Tunnel on the `onestack-sandbox` guest (ingress in `/etc/cloudflared/config.yml`, E2B client proxy on port 3002). The domain was `digitalnachos.com.au`, so a proxied `*.digitalnachos.com.au` wildcard sent every unused subdomain of the company domain to the sandbox proxy. Sandboxes run untrusted code, and the company domain also carries the invoices app, the hub, the proposal manager and their Cloudflare Access login, so sandbox pages could set cookies for all of them and stray or typo'd names (and scanners) landed on the sandbox service. The existing `*.e2b.digitalnachos.com.au` record was tried first and failed: Cloudflare's Universal SSL certificate covers one wildcard level only, so second-level names fail the TLS handshake.

## Decision

Sandbox addresses use `*.digitalnachos.com`, a separate registrable domain already in the same Cloudflare account, whose free certificate covers its first-level wildcard. Open-Inspect sets `E2B_SANDBOX_DOMAIN=digitalnachos.com`; the `digitalnachos.com` zone has a proxied `*` CNAME to the `open-inspect-sandbox` tunnel; the tunnel's ingress has a `*.digitalnachos.com` rule to port 3002. The `*.digitalnachos.com.au` wildcard record and its ingress rule are removed. Named sandbox hosts (`e2b-api.`, `e2b-sandbox.`) and Open-Inspect's own hosts (`agents.`, `agents-api.`) keep their explicit `.com.au` records.

## Consequences

Sandbox content no longer shares cookies with the `.com.au` apps and Access, and unused `.com.au` names no longer resolve. Sandbox pages do appear under the `digitalnachos.com` brand, whose apex serves the company site and which receives email through Proton, so a Safe Browsing or spam-list flag on a sandbox page could affect that domain. Any new wildcard on `digitalnachos.com` would collide with this one, and named hosts on that zone need explicit records. The `*.e2b.digitalnachos.com.au` record and ingress rule remain but cannot serve HTTPS; they can be removed in a later tidy-up.

## Alternatives considered

- `*.e2b.digitalnachos.com.au`: no edge certificate covers a second-level wildcard without Cloudflare Advanced Certificate Manager (paid); tested and failed on 23 October 2026.
- A Worker's workers.dev address: workers.dev routes the first label to a Worker name and has no wildcard below a Worker, and path-based sandbox URLs would break apps running inside sandboxes.
- A separate domain bought only for sandboxes: the strongest isolation (no shared brand or mail reputation) and still the better long-term option; not chosen now because it needs a purchase and `digitalnachos.com` was free and immediate.
