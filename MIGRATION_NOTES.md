# Migration Notes — Roadmap v2

This repo has been refactored from the original phase structure into a clearer v2 learning spine.

## Why v2 exists
The old structure had strong material, but it mixed some concerns that are better learned separately for backend/production reality:
- concurrency was under-emphasized as a top-level phase
- optimizer internals and performance tuning were too close together
- storage and durability were coupled in one phase

## New canonical sequence

```text
0. System boundaries
1. Storage
2. Concurrency
3. Durability
4. Optimizer
5. Performance tuning
6. Replication / HA / Operations
```

## Mapping: legacy -> v2

| Legacy material | v2 destination |
|---|---|
| `phase-1-architecture/*` | `phase-0-system-boundaries/*` |
| `phase-2-storage-durability/*` (storage parts) | `phase-1-storage/*` |
| `phase-2-storage-durability/*` (durability parts) | `phase-3-durability/*` |
| implicit MVCC/locking concepts formerly embedded in storage material | `phase-2-concurrency/*` |
| `phase-3-query-optimization/*` | `phase-4-optimizer/*` |
| `phase-4-query-performance/*` | `phase-5-performance-tuning/*` |
| `phase-5-scale-production/*` | `phase-6-replication-ha-ops/*` |

## Current migration status
- v2 phase folders 0–6 exist
- every v2 phase now has:
  - `README.md`
  - `read-1min.md`
  - `read-5min.md`
  - `read-10min.md`
  - `read-full.md`
- legacy folders are retained as source material and backward compatibility reference

## Canonical reading path now
1. `README.md`
2. `roadmap-v2.md`
3. `first-principles-learning.md`
4. current v2 phase folder
5. `production-symptom-map.md`
6. `cheatsheet.md`

## Legacy policy
Legacy phase folders are not removed yet. They remain useful for:
- source material
- backward compatibility
- comparing old grouping vs v2 grouping

But for new study flow, prefer v2 folders.
