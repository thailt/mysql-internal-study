# Phase 2 — Concurrency

> Many users touch the same data at once. How does MySQL stay correct without collapsing throughput?

## Core question
- How can readers and writers coexist?
- Why does MVCC exist?
- Why are old versions needed?
- Why do gap/next-key locks exist?

## Focus
- transaction lifecycle
- isolation levels
- MVCC
- undo log
- read view
- consistent read
- record lock
- gap lock
- next-key lock
- deadlock detection
- long transaction impact

## Primary reading
- Canonical sequence and first-principles framing: `../roadmap-v2.md`, `../first-principles-learning.md`
- This phase is a new explicit backbone in v2 and should be developed as a dedicated content track.
- For supporting intuition, reuse durability/storage references where undo/redo/read view interactions appear.

## Expected outputs
- explain MVCC without buzzwords
- compare repeatable read vs read committed in practical terms
- explain why deadlocks are normal, not exceptional

## Lab prompts
- open 2-3 sessions and reproduce lock waits / deadlock
- inspect `SHOW ENGINE INNODB STATUS`
- compare snapshot reads vs locking reads

## Production bridge
Typical symptoms mapped here:
- deadlock storms
- lock wait timeout spikes
- throughput collapse under write contention
- purge lag / long transaction side effects

## Reading ladder
- `read-1min.md`
- `read-5min.md`
- `read-10min.md`
- `read-full.md`

## Note
This repo previously underemphasized concurrency as a top-level phase. In roadmap v2, it is a first-class pillar.
