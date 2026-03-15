# Migration Notes — Roadmap v2

This repo was refactored from the original phase structure into a clearer v2 learning spine.

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

## Historical mapping (legacy -> v2)

| Historical material | v2 destination |
|---|---|
| phase-1 architecture | `phase-0-system-boundaries/*` |
| phase-2 storage/durability (storage concerns) | `phase-1-storage/*` |
| phase-2 storage/durability (durability concerns) | `phase-3-durability/*` |
| MVCC/locking concerns formerly embedded in older material | `phase-2-concurrency/*` |
| phase-3 query optimization | `phase-4-optimizer/*` |
| phase-4 query performance | `phase-5-performance-tuning/*` |
| phase-5 scale/production | `phase-6-replication-ha-ops/*` |

## Migration status
- v2 phase folders 0–6 exist
- every v2 phase has:
  - `README.md`
  - `read-1min.md`
  - `read-5min.md`
  - `read-10min.md`
  - `read-full.md`
- legacy phase folders have been retired and removed from the working tree

## Canonical reading path now
1. `README.md`
2. `roadmap-v2.md`
3. `first-principles-learning.md`
4. current v2 phase folder
5. `production-symptom-map.md`
6. `cheatsheet.md`

## Notes
The historical mapping remains documented here so the phase-number transition is still understandable even though the old folders are no longer present.
