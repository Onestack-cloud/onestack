# ADR-0008: Right-size the guest VMs and disable host-side disk caching

- Status: Accepted
- Date: 2026-10-07
- Authors: George Vlachos

## Context

The production host (12 cores, 63 GiB RAM, Samsung PM983 NVMe) runs three libvirt guests: `onestack-ci-runner` (13 GitHub Actions runners), `onestack-sandbox` (E2B sandbox orchestration) and `onestack-codex`. Between them they were allocated 48 GiB. The host had swapped about 134 GiB out since its last boot, 30 of its 31 GiB of swap was in use (29 GiB of it guest memory) and free RAM had dropped to 361 MiB. Each qcow2 disk used the default host page cache, so guest data was cached twice: once in the guest and again on the host, where it reached up to 40 GiB per guest and pushed idle guest memory into swap. Nine days of in-guest `sysstat` history showed peak memory used, excluding cache, of 16.8 GiB on the CI runner (13 to 17 GiB on busy days), a steady 9.4 to 10 GiB on the sandbox (an 8 GiB huge-page pool for E2B microVMs plus about 1.6 GiB of processes) and 2.9 GiB on Codex, usually under 1 GiB.

## Decision

The guests are sized from measured in-guest use with a few GiB of headroom, not from host-side resident memory, which counts guest page cache. All guest disks use `cache='none'` with `io='native'`, and all memory balloons use `freePageReporting='on'`:

- `onestack-ci-runner`: 24 GiB to 20 GiB.
- `onestack-sandbox`: 16 GiB to 12 GiB.
- `onestack-codex`: 8 GiB to 5 GiB.

Any guest created or rebuilt must use the same disk and balloon settings. The September `virt-install` scripts kept as maintenance receipts do not set them.

## Consequences

Guest allocations total 37 GiB instead of 48 GiB. Right after the change, host swap use fell from 30 GiB to 2 GiB and free RAM rose from about 14 GiB to 26 GiB. Guests no longer compete with a redundant host cache, and freed guest memory returns to the host. Guest `fsync` still reaches the disk, so durability is unchanged. Cold reads that the host cache used to serve now come from NVMe, which costs little on this hardware. The sandbox has about 2 GiB of headroom outside its huge-page pool, so it should go back to 13 or 14 GiB if ClickHouse or its other services grow. The CI runner's busiest observed days would leave about 3 GiB free, so it should grow again if more runners or heavier jobs are added. The previous domain definitions and before and after state are kept in `/root/backups/vm-resize-20261007` on the host.

## Alternatives considered

- **Keep the allocations and add swap.** This would hide the pressure without removing the double caching that caused it.
- **Shrink the sandbox's huge-page pool.** This would cut E2B's microVM capacity, which is the sandbox's purpose.
