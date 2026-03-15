# Phase 3 — Durability (10 minutes)

## The root problem

A database engine updates data in memory because that is fast.
But commit has to mean something stronger than “it was in RAM for a while”.

So durability starts from a very simple physical truth:

```text
RAM is fast but volatile
disk is durable but slower
```

The engine must bridge those two worlds without making every commit unbearably slow.

---

## 1. Why flushing full data pages on every commit is not viable
Suppose every transaction modified a row and then had to flush the entire affected page directly to its final data-file location before commit returned.

That would mean:
- lots of random I/O
- high commit latency
- terrible throughput under write-heavy workloads

So the engine needs a cheaper durable representation of the change.

---

## 2. WAL: log before data flush
The core idea is:

> make the change durable in the log before requiring the affected data page to be durably written

That is **write-ahead logging**.

Instead of saying “the table page must be on disk before commit”, the engine says:
- “the change must be durably represented in redo before commit is acknowledged”

This is a major design win because log writes are much more friendly than scattered page flushes.

---

## 3. Redo log
The **redo log** records enough information to reapply committed changes during recovery.

The key mental model is:
- buffer pool may contain newer dirty state
- data files may lag behind that state
- redo log bridges the gap

So committed work is safe because the engine can reconstruct it, even if the corresponding data page was never flushed before the crash.

This is why:
- a transaction can commit
- the page can still be dirty in memory
- crash recovery can still restore the committed result

---

## 4. Log buffer and log flush intuition
The engine also needs an in-memory area where redo is assembled before being flushed to durable log files.
That is the log buffer.

Then the durability question becomes:
- when is redo only in memory?
- when is redo safely flushed?
- when can COMMIT return?

Durability-related settings influence this boundary and therefore affect both performance and data-loss risk.

---

## 5. LSN: the ordering of durability progress
The engine needs a monotonic notion of progress across redo generation and flush.
That is the **LSN**.

You can think of it as the position in the redo timeline.

It helps reason about:
- current redo generation point
- how far flush has advanced
- how far checkpoint has advanced
- where recovery should start after crash

LSN is one of the core “clocks” of InnoDB durability.

---

## 6. Dirty pages and why they are acceptable
A dirty page is not a failure.
It is a normal consequence of decoupling memory update from data-file flush.

A page becomes dirty because:
- the logical row update happened in memory
- but persistence of the final page image is deferred

This is acceptable because redo log already protects the durability of the committed change.

So dirty pages are not evidence of weak durability.
They are evidence of a high-performance architecture that separates:
- logical change persistence in redo
- physical page persistence later

---

## 7. Checkpoint: why redo space can be reused
Redo logs are finite.
If dirty pages never flush to data files, the engine could never reuse older log space.
Eventually the log would fill.

So the engine needs a notion of:
- which earlier changes are already reflected safely in data files
- and therefore which redo space is now reclaimable

That notion is the **checkpoint**.

Checkpoint is therefore not just an implementation detail.
It is the control mechanism that keeps log-based durability sustainable over time.

---

## 8. Doublewrite and torn-page risk
There is another durability problem:
- even if flushing a page is conceptually correct
- the physical write of a page may not be atomic

If a crash happens mid-page-write, the page could end up partially old and partially new.
That is a **torn page**.

This is why InnoDB uses the **doublewrite buffer**.

The first-principles reason is simple:

> if page writes are not inherently safe against crash interruption, create a safer intermediate write path so recovery has a trustworthy copy

Doublewrite is therefore page-integrity protection, not just “extra logging”.

---

## 9. Crash recovery
After a crash, the database must come back to a consistent state.

High-level flow:

### Step 1 — find the restart point
Use checkpoint/log state to know where recovery work begins.

### Step 2 — redo committed work
Replay redo records so committed changes that were not yet reflected in data files become reflected.

### Step 3 — undo incomplete work
If transactions were in progress but not committed at crash time, rollback machinery and undo information restore consistency.

This is why recovery is usually summarized as:

```text
redo committed changes
undo incomplete changes
```

That short phrase carries a lot of engineering underneath it.

---

## 10. What COMMIT actually means
At an intuition level, COMMIT does **not** mean:
- every changed page is already in its final place in the data files

It means something closer to:

> the engine has durably recorded enough information that this transaction’s committed effects can survive crash and be recovered

That is a much more accurate mental model.

This is one of the most important conceptual upgrades for backend engineers.

---

## 11. Application and operations implications
This phase affects practical engineering decisions more than many people think.

### For backend engineers
It helps explain:
- why commit latency exists
- why batching can behave differently from many tiny commits
- why some durability settings trade safety for speed

### For production operations
It helps explain:
- why checkpoint pressure matters
- why recovery time can vary
- why storage quality affects commit behavior
- why redo saturation can stall systems

---

## 12. Production symptom map for this phase

### Symptom: commit latency spikes
Possible causes:
- redo flush cost
- storage fsync behavior
- checkpoint pressure

### Symptom: system stalls under sustained write load
Possible causes:
- redo generation outrunning flush progress
- checkpoint lag
- dirty page pressure

### Symptom: crash recovery takes unexpectedly long
Possible causes:
- lots of redo to replay
- many dirty/unsettled changes at crash time
- large amount of incomplete work to unwind

### Symptom: durability confusion in architecture discussion
Typical misunderstanding:
- assuming commit means data file is already fully updated

---

## The compact mental model

```text
updates happen in memory
  -> memory is volatile
  -> use WAL
  -> redo log makes committed change recoverable
  -> data page can flush later
  -> checkpoint allows redo reuse
  -> doublewrite protects page integrity
  -> recovery = redo committed work + undo incomplete work
```

## What you should be able to explain after this phase
1. why WAL exists
2. why redo log is enough for durable commit semantics
3. why dirty pages are normal
4. why checkpoint is necessary
5. why doublewrite exists
6. why crash recovery is redo + undo, not just “read files back”
