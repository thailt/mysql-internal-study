# Phase 2: The Disk Problem — Storage & Durability (Week 3–5)

> *Disk is 1000x slower than memory, and memory is volatile. How do we build a fast, durable database?*

Every design decision in this phase traces back to one physical constraint: **disk is slow**. InnoDB doesn't use pages, buffer pools, and write-ahead logs because someone thought they were elegant — it uses them because the hardware leaves no other choice.

## First Principles (Nguyên lý 1, 2, 4)

- **1. Lưu trữ:** Cache disk trong RAM thế nào? Đơn vị I/O? Eviction? → 2.1 Page I/O & Buffer Pool.
- **2. Tìm dữ liệu:** O(log n) lookup, range scan, clustered vs secondary? → 2.2 B+ Tree & Data Organization.
- **4. Bền vững:** Commit = gì trên disk? Crash recovery? Torn page? → 2.3 WAL & Redo Log, 2.4 Checkpoint & Doublewrite.
- **Ánh xạ đầy đủ:** [first-principles-learning.md](../first-principles-learning.md) → Nguyên lý 1, 2, 4.

## Why This Phase?

Phase 1 showed that the executor calls the storage engine via the Handler API. But *how* does the storage engine actually read and write data? Why doesn't InnoDB just `read()` and `write()` individual rows from files?

Because a single SSD read takes **~100μs** vs **~100ns** for RAM — a **1000x** gap. And RAM is volatile: power off = data gone. Every mechanism in this phase exists to bridge that gap.

## The Constraint Chain

Each topic derives from a physical constraint. Nothing is arbitrary:

```
Disk slow (100μs SSD vs 100ns RAM)
  → Read/write in pages (16KB batch I/O) → Buffer Pool (cache in RAM)
    → RAM limited → LRU with midpoint insertion
    → Modified in RAM → dirty pages
      → Volatile → Write-Ahead Logging (redo log)
        → Redo log finite → Checkpoint
        → Half-written page → Doublewrite buffer
  → Need fast lookup → B+ Tree (node = page = 1 I/O)
```

**2.1** solves the speed gap (page I/O + buffer pool).
**2.2** solves the lookup problem (B+ Tree).
**2.3** solves the volatility problem (WAL + redo log).
**2.4** solves the finite log + torn page problems (checkpoint + doublewrite).

## Topic Map

```
┌─────────────────────────────────────────────────────────┐
│              PHYSICAL CONSTRAINT: Disk is slow           │
├─────────────────────────┬───────────────────────────────┤
│  2.1 Page I/O &         │  2.2 B+ Tree &                │
│  Buffer Pool            │  Data Organization             │
│  (batch I/O, cache      │  (node = page = 1 I/O,        │
│   in RAM, LRU, dirty    │   clustered + secondary index, │
│   pages, flushing)      │   bookmark lookup, page split) │
├─────────────────────────┴───────────────────────────────┤
│              PHYSICAL CONSTRAINT: RAM is volatile        │
├─────────────────────────┬───────────────────────────────┤
│  2.3 Write-Ahead        │  2.4 Checkpoint,               │
│  Logging & Redo Log     │  Doublewrite & Crash Recovery  │
│  (sequential I/O,       │  (reclaim log space, torn page │
│   LSN, log buffer,      │   protection, redo + undo      │
│   flush-at-commit)      │   recovery flow)               │
└─────────────────────────┴───────────────────────────────┘
```

---

## 2.1 Page I/O & Buffer Pool

**Goal**: Understand why InnoDB reads data in 16KB pages and how the buffer pool eliminates most disk I/O.

**Why?** A single disk seek costs ~100μs. Reading one row at a time would be catastrophic. Instead, InnoDB batches I/O into **16KB pages** and keeps a large **in-memory cache** (the buffer pool) so that most reads never touch disk at all. The question then becomes: when the cache is full, which pages do you evict?

**Key Concepts**:
- **Page-based I/O**: all reads/writes operate on **16KB pages** — the fundamental unit of storage. One page holds many rows. One disk I/O = one page
- **Buffer pool**: large in-memory region (`innodb_buffer_pool_size`) that caches data and index pages. This is the single most important tuning knob in InnoDB
- **Three lists** manage the buffer pool:
  - **Free list**: pages not yet used (available for loading new data)
  - **LRU list**: pages currently cached, ordered by recency of access
  - **Flush list**: dirty pages ordered by oldest modification LSN (for efficient flushing)
- **LRU young/old sublists**: the LRU list is split at a **midpoint** into a **young sublist** (hot, frequently accessed) and an **old sublist** (cold, recently loaded)
- **Midpoint insertion**: new pages enter at the old sublist head (not the front of LRU). This protects hot pages from being evicted by one-time full table scans
- **`innodb_old_blocks_pct`** (default **37%**): percentage of LRU list reserved for the old sublist
- **`innodb_old_blocks_time`** (default **1000ms**): a page must be accessed again after this delay to be promoted to the young sublist — prevents scan pages from polluting young
- **Dirty pages**: pages modified in memory but not yet written to disk. Tracked on the **flush list**
- **Adaptive flushing**: background page cleaner threads flush dirty pages based on redo log generation rate, not just LRU pressure
- **Multiple buffer pool instances** (`innodb_buffer_pool_instances`): reduces mutex contention by partitioning the pool
- **Buffer pool hit ratio**: target **>99%** in production. Below 95% means too many disk reads

**Lab**:
```sql
-- Buffer pool configuration
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'innodb_buffer_pool_instances';
SHOW VARIABLES LIKE 'innodb_old_blocks_pct';
SHOW VARIABLES LIKE 'innodb_old_blocks_time';
SHOW VARIABLES LIKE 'innodb_page_size';

-- Buffer pool stats (one row per instance)
SELECT POOL_ID, POOL_SIZE, FREE_BUFFERS, DATABASE_PAGES,
       OLD_DATABASE_PAGES, MODIFIED_DB_PAGES, HIT_RATE
FROM information_schema.INNODB_BUFFER_POOL_STATS\G

-- Buffer pool hit ratio from global status
SELECT
  ROUND((1 - (reads.v / requests.v)) * 100, 2) AS hit_ratio_pct
FROM
  (SELECT VARIABLE_VALUE AS v FROM performance_schema.global_status
   WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') reads,
  (SELECT VARIABLE_VALUE AS v FROM performance_schema.global_status
   WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests') requests;

-- Pages breakdown
SHOW STATUS LIKE 'Innodb_buffer_pool_pages%';

-- Which tables occupy the buffer pool?
SELECT object_schema, object_name, allocated, data, pages
FROM sys.innodb_buffer_stats_by_table
WHERE object_schema = 'lab';
```

```sql
-- Observe dirty pages: modify data then check dirty count
UPDATE lab.employees SET salary = salary + 1 WHERE id = 1;

SHOW STATUS LIKE 'Innodb_buffer_pool_pages_dirty';
```

**Read**:
- [InnoDB Buffer Pool](https://dev.mysql.com/doc/refman/8.4/en/innodb-buffer-pool.html)
- *High Performance MySQL* Ch.4 — Buffer Pool section

**Deliverable**: Draw a buffer pool diagram showing the **free list**, **LRU list** (with young/old sublists and midpoint), and **flush list**. Explain the full page lifecycle: disk → old sublist → young sublist → dirty → flush list → flushed to disk → clean.

---

## 2.2 B+ Tree & Data Organization

**Goal**: Understand how InnoDB organizes data so that finding a row requires the minimum number of disk reads.

**Why?** Even with a buffer pool, we need to *find* the right page. A table with 10 million rows stored across thousands of pages — how do we locate the page containing `id = 42` without scanning all of them? The answer: a **B+ Tree**, where each internal node fits in one page and each tree level costs exactly one I/O. A 3-level tree with 16KB pages can index **~2 billion rows** with just 3 disk reads.

**Key Concepts**:
- **Clustered index**: the primary key IS the data. Leaf nodes contain the full row, ordered by PK. **Every InnoDB table has exactly one clustered index**
- **Clustered index selection**: explicit PK → first `UNIQUE NOT NULL` index → hidden **6-byte row ID** generated by InnoDB
- **Secondary index**: leaf nodes store the **PK value** (not a row pointer). This means secondary indexes are stable across page moves — they don't store physical addresses
- **Bookmark lookup** (a.k.a. double lookup): query uses secondary index → finds PK → traverses clustered index → gets full row. **Two B+ Tree traversals**
- **Covering index**: if all columns needed by the query are in the index itself, InnoDB skips the bookmark lookup entirely (EXPLAIN shows `Using index`)
- **Page splits**: when a leaf page is full and a new row must be inserted, the page **splits into two**. This is expensive: allocates a new page, redistributes rows, updates parent pointers. Random PK (e.g., UUID) causes frequent splits
- **Page merges**: when a page drops below **`MERGE_THRESHOLD`** (default **50%** utilization), InnoDB attempts to merge it with a neighboring page to reclaim space
- **B+ Tree height**: typically 3–4 levels. Level 0 = root (always cached), level 1–2 = internal nodes (usually cached), leaf = may require disk I/O

**Lab**:
```sql
-- Check index structure
SHOW INDEX FROM lab.employees;

-- Clustered index scan (PK lookup = 1 B+ Tree traversal)
EXPLAIN FORMAT=TREE SELECT * FROM lab.employees WHERE id = 100;

-- Secondary index → bookmark lookup (2 traversals)
EXPLAIN FORMAT=TREE SELECT * FROM lab.employees WHERE department = 'Engineering';

-- Covering index: no bookmark lookup needed
EXPLAIN FORMAT=TREE SELECT id, department FROM lab.employees
  WHERE department = 'Engineering';

-- Page split / merge metrics
SELECT NAME, COUNT, COMMENT FROM information_schema.INNODB_METRICS
  WHERE NAME LIKE '%index_page_split%' OR NAME LIKE '%index_page_merge%';

-- Table & index sizes from internal stats
SELECT
  index_name,
  stat_value * @@innodb_page_size AS size_bytes,
  ROUND(stat_value * @@innodb_page_size / 1024 / 1024, 2) AS size_mb
FROM mysql.innodb_index_stats
WHERE database_name = 'lab'
  AND table_name = 'employees'
  AND stat_name = 'size';
```

```bash
# InnoDB tablespace files on disk
docker exec mysql-lab ls -lh /var/lib/mysql/lab/
```

**Read**:
- [Jeremy Cole: B+ Tree Index Structures in InnoDB](https://blog.jcole.us/2013/01/10/btree-index-structures-in-innodb/)
- [InnoDB Index Types](https://dev.mysql.com/doc/refman/8.4/en/innodb-index-types.html)
- *High Performance MySQL* Ch.5 — Indexing

**Deliverable**: Draw a B+ Tree with both a clustered index and a secondary index for the `employees` table. Trace a **bookmark lookup** step by step: query arrives → secondary index traversal → PK extracted → clustered index traversal → row returned.

---

## 2.3 Write-Ahead Logging & Redo Log

**Goal**: Understand how InnoDB guarantees durability without flushing every dirty page on every commit.

**Why?** The buffer pool (2.1) keeps modified pages in RAM as **dirty pages**. But RAM is volatile — a crash loses everything not on disk. Flushing dirty data pages on every commit would be disastrous: data pages are scattered across the tablespace (**random I/O**, ~100μs per page). The solution: write a compact description of the change to a **sequential log file** first. Sequential I/O is orders of magnitude faster than random I/O. This is the **Write-Ahead Log (WAL)** principle.

**COMMIT = redo log flushed to disk.** The actual data page flush happens later, asynchronously. If the server crashes, the redo log has everything needed to reconstruct the dirty pages.

**Key Concepts**:
- **WAL principle**: sequential write to log is far faster than random write to data file. Write the log first, flush the data page later
- **Redo log**: a **circular buffer** of fixed size on disk. Records **physical changes** to pages (e.g., "page 57, offset 120, write these bytes")
- **LSN (Log Sequence Number)**: a **monotonically increasing** counter that tracks the current position in the redo log. Every page, every log record, and every checkpoint is tagged with an LSN
- **Log buffer** (`innodb_log_buffer_size`): in-memory buffer where redo log records accumulate before being written to the redo log files on disk
- **`innodb_flush_log_at_trx_commit`** — the most important durability setting:
  - **`1`** = flush to disk on every commit — **full ACID**, no data loss on crash
  - **`2`** = write to OS page cache on commit — survives mysqld crash, not OS/power crash
  - **`0`** = write to log buffer only, flush every ~1 second — fastest, up to 1 second of data loss
- **Two-phase commit** (with binlog): ensures redo log and binary log are consistent:
  1. InnoDB **prepare** (write prepare record to redo log)
  2. **Binlog write** (write transaction to binary log)
  3. InnoDB **commit** (write commit record to redo log)
  If crash after step 2 → recovery finds binlog entry → commits in InnoDB. If crash before step 2 → no binlog entry → rolls back

**Lab**:
```sql
-- Redo log configuration
SHOW VARIABLES LIKE 'innodb_redo_log_capacity';
SHOW VARIABLES LIKE 'innodb_log_buffer_size';
SHOW VARIABLES LIKE 'innodb_flush_log_at_trx_commit';

-- LSN and log status from INNODB STATUS
-- Look for the LOG section: Log sequence number, Log flushed up to, Last checkpoint at
SHOW ENGINE INNODB STATUS\G

-- Redo log metrics
SELECT NAME, COUNT, COMMENT FROM information_schema.INNODB_METRICS
  WHERE SUBSYSTEM = 'recovery' OR NAME LIKE '%log%'
  ORDER BY NAME;

-- Observe LSN change during writes
-- Run this before and after an UPDATE to see LSN advance:
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
  WHERE NAME = 'log_lsn_current' OR NAME = 'log_lsn_checkpoint_age';

UPDATE lab.employees SET salary = salary + 1 WHERE department = 'Engineering';

SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
  WHERE NAME = 'log_lsn_current' OR NAME = 'log_lsn_checkpoint_age';
```

```bash
# Redo log files on disk (MySQL 8.0.30+)
docker exec mysql-lab ls -lh /var/lib/mysql/#innodb_redo/
```

**Read**:
- [InnoDB Redo Log](https://dev.mysql.com/doc/refman/8.4/en/innodb-redo-log.html)
- *High Performance MySQL* Ch.4 — InnoDB Crash Recovery

**Deliverable**: Explain why `COMMIT` is fast even though the data hasn't been written to the tablespace yet. Answer: because COMMIT only requires a **sequential redo log write** (fast), while the actual data page flush (random I/O, slow) happens later asynchronously by background threads.

---

## 2.4 Checkpoint, Doublewrite & Crash Recovery

**Goal**: Understand how InnoDB reclaims redo log space, protects against torn pages, and recovers from arbitrary crashes.

**Why?** Three remaining problems:
1. The redo log is a **finite circular buffer**. If dirty pages are never flushed, the log fills up and all writes stall. **Checkpoints** advance the flush position so old log space can be reused.
2. A 16KB page write is not atomic on most hardware — a crash mid-write produces a **torn page** (half old, half new data, both halves corrupt). The **doublewrite buffer** solves this.
3. A crash can happen at any point — mid-transaction, mid-flush, mid-checkpoint. **Crash recovery** must handle all cases automatically.

**Key Concepts**:
- **Checkpoint**: the **LSN** up to which all dirty pages have been flushed to disk. Redo log space before the checkpoint LSN can be safely reused
- **Sharp checkpoint**: flush ALL dirty pages at once. Used only at **clean shutdown** (`innodb_fast_shutdown = 0`)
- **Fuzzy checkpoint**: flush dirty pages **gradually** in the background. Used during normal operation. Multiple variants:
  - **Page cleaner flush**: background threads flush oldest dirty pages from the flush list
  - **Adaptive flushing**: adjusts flush rate based on redo log fill percentage
  - **Async/sync flush**: emergency flushing when redo log is nearly full (causes stalls — avoid this)
- **Doublewrite buffer**: before writing a dirty page to its actual tablespace location, InnoDB writes it to a **doublewrite area** first (sequential I/O). Then it writes to the actual location. If a crash happens during the actual write → the doublewrite copy is intact → recovery uses it to restore the page. If a crash happens during the doublewrite write → the original page is still intact on disk
- **Crash recovery flow** (fully automatic, no manual intervention):
  1. **Scan redo log** from the last checkpoint LSN
  2. **REDO phase**: replay all redo log records after the checkpoint. These operations are **idempotent** — safe to replay even if the page was already flushed
  3. **UNDO phase**: find all transactions that were active (uncommitted) at the time of crash. Roll them back using the **undo log**
  4. After recovery: database is consistent, all committed transactions are present, all uncommitted transactions are rolled back
- **Recovery is automatic**: `mysqld` performs crash recovery on startup — no DBA intervention required (unlike MyISAM's `REPAIR TABLE`)

**Lab**:
```sql
-- Checkpoint vs current LSN (gap = dirty data not yet flushed)
-- In INNODB STATUS LOG section:
--   Log sequence number = current LSN
--   Last checkpoint at  = checkpoint LSN
--   Gap = amount of redo log that cannot be reused yet
SHOW ENGINE INNODB STATUS\G

-- Checkpoint age (how far behind the checkpoint is)
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
  WHERE NAME IN ('log_lsn_current', 'log_lsn_last_checkpoint',
                 'log_lsn_checkpoint_age');

-- Doublewrite buffer stats
SHOW STATUS LIKE 'Innodb_dblwr%';

-- Redo log capacity
SHOW VARIABLES LIKE 'innodb_redo_log_capacity';
SHOW VARIABLES LIKE 'innodb_fast_shutdown';

-- Observe checkpoint advance: do heavy writes, then wait for flush
UPDATE lab.employees SET salary = salary + 1;

-- Check checkpoint age before and after a few seconds
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
  WHERE NAME = 'log_lsn_checkpoint_age';
```

```bash
# Doublewrite files (MySQL 8.0.20+)
docker exec mysql-lab ls -lh /var/lib/mysql/#ib_*_*

# Redo log files
docker exec mysql-lab ls -lh /var/lib/mysql/#innodb_redo/
```

**Read**:
- [InnoDB Crash Recovery](https://dev.mysql.com/doc/refman/8.4/en/innodb-recovery.html)
- [InnoDB Doublewrite Buffer](https://dev.mysql.com/doc/refman/8.4/en/innodb-doublewrite-buffer.html)

**Deliverable**: Explain crash recovery step by step. Draw a timeline showing a write operation, then a crash at different points (before redo flush, after redo flush but before data page flush, during data page flush). For each crash point, explain what recovery does and when the doublewrite buffer matters.

---

## How It All Fits Together — The Complete Write Path

Every `UPDATE` touches all four mechanisms in sequence:

```
Application: UPDATE employees SET salary = 50000 WHERE id = 42;

  1. [Buffer Pool — 2.1]
     Page containing id=42 loaded into buffer pool (if not already cached).
     Row modified IN MEMORY. Page marked DIRTY.

  2. [B+ Tree — 2.2]
     Clustered index traversal: root → internal → leaf page.
     If secondary index column changed → update secondary index too.

  3. [Redo Log — 2.3]
     Change record written to LOG BUFFER.
     On COMMIT: log buffer flushed to REDO LOG on disk (sequential I/O).
     → Transaction is now DURABLE even though data page is still dirty in RAM.

  4. [Checkpoint & Doublewrite — 2.4]
     Later, page cleaner thread picks up the dirty page.
     Writes page to DOUBLEWRITE BUFFER first (torn page protection).
     Then writes page to its TABLESPACE location (actual .ibd file).
     CHECKPOINT advances → redo log space reclaimed.

  Crash at any point?
     → Before step 3: transaction not committed, nothing to recover.
     → After step 3, before step 4: REDO phase replays from redo log.
     → During step 4 (torn page): doublewrite copy restores the page,
       then redo log replays if needed.
```

---

## Progress Tracker

| # | Topic | Status |
|---|-------|--------|
| 2.1 | Page I/O & Buffer Pool | [ ] |
| 2.2 | B+ Tree & Data Organization | [ ] |
| 2.3 | Write-Ahead Logging & Redo Log | [ ] |
| 2.4 | Checkpoint, Doublewrite & Crash Recovery | [ ] |

---

**What's next?** Phase 3 zooms into the concurrency problem: multiple transactions reading and writing the same data simultaneously. How does InnoDB let readers and writers coexist without chaos? The answer involves **MVCC**, **undo logs**, **row locks**, **gap locks**, and **deadlock detection** — all derived from the constraint that **shared mutable state requires coordination**.
