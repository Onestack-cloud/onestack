# ADR-0004: One shared, linear-time heuristic redaction module for Worker logs

- Status: Accepted
- Date: 2026-10-07
- Authors: George Vlachos

## Context

The Cloudflare logs stack writes Worker logs to Loki from two places: the live ingest adapter (`ingest/server.js`) and the backfill script (`scripts/backfill-workers-observability.mjs`). Each had its own redaction code and they had drifted apart. The adapter only redacted sensitive object keys, so secrets in URL query strings, structured `console.log` arguments and exception messages reached Loki, and the backfill wrote some messages raw. Log content is shaped by Worker code and by whoever sends requests to the Workers, so redaction runs on attacker-influenced input inside the ingest event loop. Review rounds found quadratic regexes that could stall ingest for seconds on a 160 KB string. Repeated security scans kept finding further edge cases, which showed that any redaction of free-form logs is heuristic.

## Decision

`ingest/redaction.js` is the single redaction implementation for every path that writes Worker logs to Loki. The ingest image ships it, and the backfill script loads it relative to its own file. Redaction is best effort and its coverage is documented in the stack README:

- It redacts values under sensitive key names anywhere in a record, including console arguments, header lists and strings that are entirely JSON. Flags and counter-like numbers stay visible.
- In any `scheme://` URL it redacts userinfo and sensitive query or fragment parameters, rewriting only those parts as text.
- In free text it redacts `Bearer` and `Basic` credentials and sensitive `name=value` or `name: value` pairs, quoted or not.
- It deliberately does not redact secrets in URL paths (such as webhook URLs), unnamed secrets in prose or JSON fragments it cannot parse, so Workers must not log those.

Every pattern in the module must run in linear time, with bounded repetition where needed, and values nested deeper than 64 levels are replaced outright. Each new rule comes with tests for the leak it closes, the context it must leave alone and adversarial timing.

## Consequences

Live and backfilled logs are redacted identically, and a gap fixed once is fixed for both. The ingest adapter cannot be stalled by crafted log content through redaction. Redaction is a safety net rather than a guarantee: secrets that Workers log in unsupported shapes still reach Loki, so the real control is not logging secrets in Worker code. Heuristics trade some over-redaction (for example a value after a bare `session` argument) against leaks, and each new rule needs a decision about that balance. Moving or renaming `ingest/` breaks the backfill's relative import, which the README command depends on.

## Alternatives considered

- **Separate redaction in each writer.** This was the starting point, and the two copies had already diverged in what they leaked.
- **Key-only redaction.** This is simpler and never over-redacts, but it missed secrets in URLs, console arguments and exception messages, which is where they were actually leaking.
