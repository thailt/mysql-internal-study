# Phase 2: InnoDB Deep Dive — Full content

Understand InnoDB's internal data structures, transaction mechanics, and crash recovery guarantees.

> Each topic below is **self-contained**. Jump into any item freely — prerequisites are noted where needed.

## Topic Map

```
┌─────────────────────────────────────────────────────┐
│              2.1 Buffer Pool                         │
│    (page-based I/O, LRU, dirty page flushing)       │
├─────────────────────────────────────────────────────┤
│              2.2 B+ Tree Index                       │
│    (clustered index, secondary index, page splits)   │
├──────────────────────┬──────────────────────────────┤
│ 2.3 Transaction &    │ 2.4 Locking                   │
│ MVCC                 │ (row lock, gap lock,           │
│ (undo log, read view,│  next-key lock, deadlock)      │
│  snapshot isolation)  │                               │
├──────────────────────┴──────────────────────────────┤
│              2.5 Redo Log & WAL                      │
│    (crash recovery, checkpoint, doublewrite buffer)   │
└─────────────────────────────────────────────────────┘
```

---

## 2.1 Buffer Pool

**Goal**: Understand how InnoDB manages data in memory using page-based I/O.

**Key Concepts**:
- InnoDB reads/writes data in **16KB pages** (not individual rows)
- Buffer pool = large in-memory cache of data and index pages
- Three key lists: **free list** (unused pages), **LRU list** (cached pages), **flush list** (dirty pages)
- LRU has **young sublist** (hot, frequently accessed) and **old sublist** (cold, recently loaded)
- New pages enter at the **midpoint** (old sublist head), promoted to young after second access within `innodb_old_blocks_time`
- **Adaptive flushing**: background thread flushes dirty pages based on redo log generation rate
- Multiple buffer pool instances reduce mutex contention

**Lab**:
```sql
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'innodb_buffer_pool_instances';
SHOW VARIABLES LIKE 'innodb_old_blocks_pct';
SHOW VARIABLES LIKE 'innodb_old_blocks_time';
SELECT * FROM information_schema.INNODB_BUFFER_POOL_STATS\G
-- Hit ratio: (1 - Innodb_buffer_pool_reads/Innodb_buffer_pool_read_requests)*100
SHOW STATUS LIKE 'Innodb_buffer_pool_pages%';
SELECT * FROM sys.innodb_buffer_stats_by_table WHERE object_schema = 'lab';
```

**Read**: InnoDB Buffer Pool (MySQL docs), *High Performance MySQL* Ch.4, Percona: Buffer Pool Internals.

**Deliverable**: Draw buffer pool diagram (LRU young/old, free list, flush list) and explain when a page moves between lists.

---

## 2.2 B+ Tree Index

**Goal**: Understand how InnoDB organizes data on disk using B+ Tree structures.

**Key Concepts**:
- **Clustered index**: leaf nodes = full row, ordered by PK; one per table; no PK → first UNIQUE NOT NULL or hidden row ID
- **Secondary index**: leaf = PK value (bookmark lookup: secondary → PK → clustered)
- **Page splits/merges**: full leaf → split; below MERGE_THRESHOLD → merge. **Index merge**: optimizer can combine multiple single-column indexes

**Lab**: SHOW INDEX; EXPLAIN FORMAT=TREE (PK vs secondary vs covering); INNODB_METRICS index_page; innodb_index_stats.

**Deliverable**: Draw B+ Tree (clustered + secondary) for `employees` and trace a bookmark lookup.

---

## 2.3 Transaction & MVCC

**Goal**: Understand snapshot isolation without blocking readers.

**Key Concepts**:
- ACID; isolation levels READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ (default), SERIALIZABLE
- **Undo log**: old row versions for rollback and MVCC. **Read view**: snapshot of active trx IDs (RR: first read; RC: per statement). Visibility: trx_id rules
- **Purge**: cleans undo no longer needed. Long transactions → undo bloat

**Lab**: RR vs RC demo (two sessions); INNODB_TRX; Innodb_purge%; INNODB_METRICS trx_undo/purge.

**Deliverable**: Demo RR vs RC; explain read view visibility with a concrete example.

---

## 2.4 Locking

**Goal**: Row-level locking and deadlock handling.

**Key Concepts**:
- **Record lock**, **gap lock**, **next-key lock** (record + gap before). **Intention locks** (IS, IX). **Insert intention lock**
- **Deadlock detection**: wait-for graph; rollback smaller transaction. RC: record locks only

**Lab**: data_locks, data_lock_waits; gap lock experiment; deadlock experiment; SHOW ENGINE INNODB STATUS → LATEST DETECTED DEADLOCK.

**Deliverable**: Create 3 deadlock scenarios; show data_locks and explain each.

---

## 2.5 Redo Log & WAL

**Goal**: Durability and crash recovery.

**Key Concepts**:
- **WAL**: write redo before flushing dirty pages. **Redo log**: circular; **LSN**; **Checkpoint**. **Doublewrite buffer**: avoid torn pages. **Crash recovery**: redo → undo. `innodb_flush_log_at_trx_commit`

**Lab**: redo/log variables; SHOW ENGINE INNODB STATUS LOG; Innodb_dblwr%; #innodb_redo/ files.

**Deliverable**: Explain crash recovery steps from server start after crash; when is doublewrite needed?

---

## How It All Fits Together

Client writes → Buffer Pool (dirty) → Redo (WAL) → B+ Tree → MVCC (undo) + Locking → Checkpoint → Crash: redo + undo rollback.

---

## Progress Tracker

| # | Topic | Status |
|---|-------|--------|
| 2.1 | Buffer Pool | [ ] |
| 2.2 | B+ Tree Index | [ ] |
| 2.3 | Transaction & MVCC | [ ] |
| 2.4 | Locking | [ ] |
| 2.5 | Redo Log & WAL | [ ] |
