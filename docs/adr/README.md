# Architecture decision records

Short records of notable product and architecture decisions for this repo.

## When to write one

- Committing to a direction that closes off alternatives.
- Introducing a cross-cutting convention (naming, structure, formatting).
- Rejecting something that someone is likely to try again later.

Skip for bug fixes, one-off implementation details, or choices that live naturally in a commit message.

## File naming

`NNNN-short-slug.md`, zero-padded, monotonically increasing. Never renumber. If a decision is reversed, write a new ADR that supersedes the old one and link both ways.

## Status values

- **Proposed**: authored, not yet signed off.
- **Accepted**: in force.
- **Superseded by ADR-XXXX**: historical only; link forward.

Don't delete ADRs; mark them superseded.
