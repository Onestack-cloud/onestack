# ADR-0006: Retire Twenty

- Status: Accepted
- Date: 2026-10-07
- Authors: George Vlachos

## Context

Twenty, a self-hosted CRM, ran on the production host with its own server, worker and PostgreSQL database behind Traefik, and the Onestack app could provision members into it. It had been upgraded to 2.38.1 during the September hardening, which left migration containers, rollback images and a staging copy behind. A security review then flagged its database route through Traefik. Before removal, usage was checked directly. No user had signed in or changed workspace membership since January 2025, and every workspace held only Twenty's starter records. The only API keys were named `test`, there were no webhooks, none of the 56 n8n workflows referenced it, and no Onestack product or member used it.

## Decision

Twenty is retired rather than kept, hardened or upgraded. On 7 October 2026 its containers, volumes, networks, images, the Traefik `twenty_db` entrypoint and its monitoring and backup entries were removed from the host. The app's Twenty product configuration and provisioning code and the repository's Compose stack were deleted. A full `pg_dumpall`, the volume archives, the stack directory with its `.env`, the maintained PostgreSQL image, its build recipe and the September staging copy are kept in `/root/backups/twenty-retired-20261007-083814` on the host.

## Consequences

The host runs 33 expected containers instead of 36. Twenty's database is no longer reachable through Traefik, and nothing remains to patch. Offering a CRM again would mean choosing and integrating one afresh. The archive allows a restore if old Twenty data is ever needed. The `twenty.onestack.cloud` DNS records, the `TWENTY_DB_*` variables in the app's production `.env` and the historical references in the off-host retention scope and backup-scope test fixture were left in place.

## Alternatives considered

- **Keep Twenty and close only the database route.** This would fix the flagged exposure but keep an unused service to patch, back up and monitor.
