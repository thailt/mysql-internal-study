# Phase 3 — Durability (Full)

## 1. Why durability is a separate discipline

Storage tells us where data lives and how it is organized.
Concurrency tells us how multiple actors safely use it.
Durability answers a different question:

> once a transaction commits, what exactly guarantees that the result survives a crash?

This is not the same as query performance and not the same as logical correctness alone.
It is about persistence under failure.

A database that is fast but loses committed work on crash is not acceptable for most OLTP systems.
So durability is one of the central promises of the engine.

---

## 2. The physical problem: memory is volatile

The engine updates data in memory because memory is fast.
But memory disappears when the process crashes or power is lost.

That creates an immediate challenge:
- in-memory updates are fast
- durable updates require storage
- storage writes are slower and often less conveniently shaped

If the engine required every modified data page to be flushed to its final on-disk location before COMMIT returned, write-heavy workloads would suffer badly.

So the engine needs a better durability representation than “flush the actual page immediately”.

---

## 3. WAL: the key architectural move

The solution is **write-ahead logging**.

The first-principles idea is:

> record the change durably in a log before relying on later page flush to make the data file itself fully up to date

This is powerful because log writes are usually much cheaper and more sequential than scattered page writes.

So WAL turns the durability problem from:
- “must flush every changed page at commit time”

into:
- “must durably flush the log record that lets us recover the change later”

This is one of the foundational ideas in database internals.

---

## 4. Redo log: durable recovery information

The redo log is the mechanism that makes WAL useful.

Its purpose is to record enough information that committed changes can be replayed after a crash.

A useful mental model:
- buffer pool may hold the newest in-memory state
- data files may still lag behind
- redo log bridges the difference between them

That means a committed transaction can be considered safe even if the modified table page is still only dirty in memory — as long as the redo needed to reconstruct it has been durably flushed.

This is a major conceptual shift.

### Commit does not mean
- every changed page is already in its final place on disk

### Commit means more like
- the engine has durably recorded enough information to recover the committed effects later

That is a more accurate way to think about durability.

---

## 5. Log buffer and flush boundary

Redo records are not written to stable storage one byte at a time directly from every CPU instruction.
There is an in-memory staging area: the log buffer.

So the important durability boundary becomes:
- redo only in memory = not yet safe enough
- redo flushed durably = safe enough for commit semantics

This is why durability-related configuration has real consequences.
It changes the boundary between:
- fast acknowledgment
- strong survival guarantee

Not all durability settings mean the same thing operationally.

---

## 6. LSN: ordering the durability timeline

The engine needs a monotonic notion of progress through redo generation.
That is the **LSN**.

LSN helps the engine reason about:
- where current redo generation is
- what portion of redo has already been flushed
- how far page flushing has caught up
- where crash recovery should begin from

In other words, LSN is one of the key coordinates in InnoDB’s durability state machine.

You should think of it as the timeline position of redo progress.

---

## 7. Dirty pages are a feature, not a failure

A dirty page is simply a page in memory whose changes are newer than what is currently stored in the data file.

This is normal.
In fact, it is necessary for high performance.

Without dirty pages, the engine would be forced to synchronize every logical update immediately to the data file, destroying throughput.

Dirty pages are safe because the redo log protects the durability of committed work.
So the architecture intentionally separates:
- logical change durability through redo
- physical page persistence later through flush

This is why you should not interpret “many dirty pages” as inherently wrong.
The question is whether the flush/checkpoint system is keeping up safely.

---

## 8. Checkpoint: why finite redo capacity is sustainable

Redo logs are finite.
If the engine kept generating redo forever without ensuring that corresponding dirty pages became durable in the data files, eventually there would be no reusable log space left.

Checkpoint solves this.

Checkpoint means:
- changes up to a certain log position are already reflected safely enough in the durable page storage
- redo before that point can be recycled

This is the bridge between:
- log progress
- data-page flush progress

Without checkpointing, WAL would not scale continuously.

### Important mental model

```text
redo generation runs ahead
page flushing catches up
checkpoint marks how much has safely caught up
```

That relationship is central to durability behavior under load.

---

## 9. Why page integrity is its own problem: torn pages

Even if you know which page needs to be flushed, another issue appears:
- a page write may not be atomic
- a crash may interrupt it halfway
- the resulting page image on disk may be corrupt or partially updated

This is the torn-page problem.

The engine therefore needs more than redo.
It also needs a safer way to materialize page images.

That is why the **doublewrite buffer** exists.

The first-principles reason is:

> if direct final-page writes can be interrupted into an invalid partial state, introduce an intermediate safer write path so recovery can rely on a valid page copy

Doublewrite is page-integrity protection.
It is not just “extra writing for fun”.

---

## 10. Crash recovery: reconstructing a consistent state

When the server restarts after a crash, it cannot assume:
- all committed pages were flushed
- all in-flight transactions finished
- all page writes completed cleanly

So recovery has to rebuild consistency.

High-level flow:

### Step 1 — identify the starting point
Use checkpoint/log state to determine where recovery work should begin.

### Step 2 — redo committed work
Replay redo so committed changes absent from the data files become present.

### Step 3 — undo incomplete work
Transactions that had not successfully committed by crash time must be rolled back using undo information.

This gives the standard summary:

```text
redo committed changes
undo incomplete changes
```

That summary is simple, but it is one of the deepest operational truths in MySQL durability.

---

## 11. Why COMMIT can be fast

Many engineers new to storage internals assume COMMIT must mean “all data is now in the table file”.
That is not how high-performance engines usually work.

COMMIT can be relatively fast because:
- the engine writes/flushes redo
- not necessarily every modified page to its final table location

This is one of the big wins of WAL.

It lets the system decouple:
- transaction acknowledgment path
- bulk physical data-page persistence path

That separation is crucial for OLTP performance.

---

## 12. Interaction with application design

Durability is not only a storage-engine topic.
It affects application behavior too.

### Commit frequency
Frequent tiny commits may create different pressure patterns from batched work.

### Durability settings
A team may unknowingly trade safety for speed if it changes log flush policy without understanding the consequences.

### Recovery expectations
Product and platform teams often ask:
- what can be lost on crash?
- how long can restart take?
- what guarantees do we actually provide?

Those questions all depend on this phase.

So durability is part of architecture, not only DBA trivia.

---

## 13. Production symptom map for durability

### Symptom: commit latency spikes
Look for:
- redo flush cost
- storage latency / fsync behavior
- checkpoint pressure

### Symptom: write-heavy workload periodically stalls
Look for:
- log generation outrunning flush/catch-up
- dirty page pressure
- checkpoint age becoming problematic

### Symptom: restart after crash takes long
Look for:
- large amount of redo to replay
- large amount of incomplete work to unwind
- write-heavy system at crash time

### Symptom: confusion around data-loss guarantees
Look for:
- misunderstanding of durability settings
- confusion between “log flushed” and “all pages flushed”
- architecture assumptions that commit implies fully materialized table files

---

## 14. Suggested labs for this phase

### Lab 1 — log-before-page intuition
- perform writes
- inspect redo/checkpoint state
- reason about why commit returned before full page flush

### Lab 2 — dirty page intuition
- generate writes
- inspect dirty page counters
- understand that dirty pages are expected

### Lab 3 — crash and recovery thought experiment
- choose different crash points conceptually:
  - before redo durable flush
  - after redo durable flush but before data-page flush
  - during page flush
- explain what recovery would do in each case

### Lab 4 — doublewrite intuition
- study torn-page problem conceptually
- explain why redo alone is not the whole story for page-image integrity

### Lab 5 — durability setting comparison
- compare conceptual guarantees of stronger vs weaker flush settings
- reason about what failures each setting survives

---

## 15. Compact mental model

Keep this chain:

```text
changes happen in memory
  -> memory is volatile
  -> use WAL
  -> redo log records recoverable change history
  -> dirty pages can flush later
  -> checkpoint controls reusable redo progress
  -> doublewrite protects page integrity
  -> recovery = redo committed work + undo incomplete work
```

---

## 16. Explain-back checklist

You should be able to explain:
1. why WAL exists
2. why redo log is enough for durable commit semantics before page flush
3. why dirty pages are expected
4. why checkpoint is required for finite logs
5. why doublewrite exists in addition to redo
6. why recovery is fundamentally redo + undo
7. why commit does not necessarily mean the page is already in final table storage

If you can explain these clearly, the durability model is landing.
