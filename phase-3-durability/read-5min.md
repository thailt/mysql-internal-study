# Phase 3 — Durability (5 minutes)

## The first-principles question

> If memory is volatile, what does COMMIT really mean, and how can the engine survive a crash?

## Start from the problem
When a row is updated, the change usually hits memory first.
But memory disappears on crash.

So the engine needs a rule:
- a committed change must not depend only on RAM

Naive option:
- flush the actual data page to disk on every commit

Problem:
- data pages are scattered
- that means expensive random I/O
- commit latency would become awful

So InnoDB uses a smarter method.

---

## 1. WAL: write-ahead logging
The key idea is:

> log the change first, flush the data page later

This is **write-ahead logging**.

Instead of forcing every commit to write the full modified page to its final place on disk, the engine writes a compact redo record first.

That log write is much cheaper than random page flushes.

---

## 2. Redo log
The **redo log** exists so committed changes can be reconstructed after crash.

A simple mental model:
- dirty pages in memory = latest state not yet safely materialized in data files
- redo log on disk = enough information to rebuild committed changes later

So commit becomes tied to redo durability, not immediate data-page durability.

---

## 3. LSN
The engine needs an ordering for redo generation.
That ordering is the **LSN**.

Think of it as the position in the redo stream.

It helps the engine reason about:
- how far the log has progressed
- how far data-page flush has caught up
- where crash recovery should start

---

## 4. Checkpoint
Redo space is not infinite.
If dirty pages never flush, the redo log would eventually fill up.

So the engine needs a way to say:
- all changes up to this point are already reflected safely in data files
- log space before that point can be reused

That point is the **checkpoint**.

Checkpoint is therefore a bridge between:
- log progress
- page flush progress

---

## 5. Doublewrite
Another durability problem is that page writes are not always atomic.
If the server crashes while writing a page, the page may be half old / half new — a torn page.

The **doublewrite buffer** exists to protect against that.
It gives the engine a safer intermediate copy path before the page lands in its final location.

---

## 6. Crash recovery
After a crash, the engine must restore a consistent state.

The high-level recovery flow is:
- replay committed changes from redo
- roll back incomplete/uncommitted work using undo

That is why durability is not just about logging.
It is about the whole recovery story.

---

## Production meaning
This phase explains:
- why COMMIT can be fast
- why dirty pages may still exist after commit
- why redo/checkpoint pressure affects system behavior
- why crash recovery can take time
- why durability settings are real trade-offs, not trivia

---

## Mental model to keep

```text
memory changes first
  -> memory is volatile
  -> log first (redo)
  -> flush data pages later
  -> checkpoint reclaims log space
  -> doublewrite protects page writes
  -> crash recovery = redo + undo
```

## If you remember 4 things
1. WAL exists because flushing full pages on every commit is too expensive.
2. Redo log makes committed changes recoverable.
3. Checkpoint exists because redo space is finite.
4. Doublewrite exists because page writes can tear on crash.
