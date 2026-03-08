# Phase 2: InnoDB Deep Dive

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
-- Buffer pool configuration
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'innodb_buffer_pool_instances';
SHOW VARIABLES LIKE 'innodb_old_blocks_pct';
SHOW VARIABLES LIKE 'innodb_old_blocks_time';

-- Buffer pool stats
SELECT * FROM information_schema.INNODB_BUFFER_POOL_STATS\G

-- Buffer pool hit ratio
SELECT
  (1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)) * 100 AS hit_ratio
FROM (
  SELECT VARIABLE_VALUE AS Innodb_buffer_pool_reads
  FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads'
) r, (
  SELECT VARIABLE_VALUE AS Innodb_buffer_pool_read_requests
  FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests'
) rr;

-- Dirty pages monitoring
SHOW STATUS LIKE 'Innodb_buffer_pool_pages%';

-- Pages by table (via sys schema)
SELECT * FROM sys.innodb_buffer_stats_by_table
  WHERE object_schema = 'lab';
```

**Read**:
- [InnoDB Buffer Pool](https://dev.mysql.com/doc/refman/8.4/en/innodb-buffer-pool.html)
- *High Performance MySQL* Ch.4 — Buffer Pool section
- Percona Blog: InnoDB Buffer Pool Internals

**Deliverable**: Draw a diagram of the buffer pool showing LRU young/old sublists, free list, and flush list. Explain when a page moves between lists.

---

## 2.2 B+ Tree Index

**Goal**: Understand how InnoDB organizes data on disk using B+ Tree structures.

**Prerequisites**: 2.1 (buffer pool) — pages are the unit of B+ Tree nodes.

**Key Concepts**:
- **Clustered index**: leaf nodes store the full row data, ordered by PK. Every InnoDB table has exactly one
- If no PK defined → first `UNIQUE NOT NULL` index → hidden 6-byte row ID
- **Secondary index**: leaf nodes store the PK value (not a row pointer)
- **Bookmark lookup** (double lookup): secondary index → get PK → clustered index → get row
- **Page splits**: when a leaf page is full, InnoDB splits it into two (costly I/O operation)
- **Page merges**: when a page drops below `MERGE_THRESHOLD` (default 50%), InnoDB merges with neighbor
- **Index merge**: optimizer can combine multiple single-column indexes (intersection/union)

**Lab**:
```sql
-- Check index structure
SHOW INDEX FROM lab.employees;
SHOW INDEX FROM lab.orders;

-- Clustered index = PK, secondary uses PK as pointer
EXPLAIN FORMAT=TREE SELECT * FROM lab.employees WHERE id = 100;
EXPLAIN FORMAT=TREE SELECT * FROM lab.employees WHERE department = 'Engineering';

-- Covering index: no bookmark lookup needed
EXPLAIN FORMAT=TREE SELECT id, department FROM lab.employees WHERE department = 'Engineering';

-- Page split / merge monitoring
SELECT NAME, COUNT, STATUS FROM information_schema.INNODB_METRICS
  WHERE NAME LIKE '%index_page%';

-- Table & index size
SELECT
  TABLE_NAME, INDEX_NAME, STAT_VALUE * @@innodb_page_size AS size_bytes
FROM mysql.innodb_index_stats
WHERE database_name = 'lab' AND stat_name = 'size';
```

```bash
# InnoDB tablespace files
docker exec mysql-lab ls -lh /var/lib/mysql/lab/
```

**Read**:
- [InnoDB Index Types](https://dev.mysql.com/doc/refman/8.4/en/innodb-index-types.html)
- [Jeremy Cole: B+ Tree Index Structures in InnoDB](https://blog.jcole.us/2013/01/10/btree-index-structures-in-innodb/)
- *High Performance MySQL* Ch.5 — Indexing

**Deliverable**: Draw a B+ Tree showing clustered index and a secondary index for the `employees` table. Trace a query that does a bookmark lookup.

---

## 2.3 Transaction & MVCC

**Goal**: Understand how InnoDB implements snapshot isolation without blocking readers.

**Prerequisites**: 2.2 (B+ Tree) — understand where row data lives.

**Key Concepts**:
- **ACID**: InnoDB guarantees atomicity (undo log), consistency, isolation (MVCC + locks), durability (redo log)
- **Isolation levels**: READ UNCOMMITTED, READ COMMITTED (RC), REPEATABLE READ (RR, default), SERIALIZABLE
- **Undo log**: stores old row versions in rollback segments. Used for rollback and MVCC reads
- **Read view**: snapshot of active transaction IDs at the time of first read (RR) or each statement (RC)
- **Visibility rules**: a row version is visible if `trx_id < min_active_trx_id` or `trx_id == current_trx_id`
- **Purge thread**: background thread that cleans up undo log entries no longer needed by any active read view
- **Long-running transactions** = undo log bloat → performance degradation

**Lab**:
```sql
-- Current isolation level
SELECT @@transaction_isolation;

-- Active transactions
SELECT * FROM information_schema.INNODB_TRX\G

-- Experiment: RR vs RC behavior
-- Session 1:
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT salary FROM lab.employees WHERE id = 1; -- snapshot taken

-- Session 2:
UPDATE lab.employees SET salary = salary + 1000 WHERE id = 1;
COMMIT;

-- Session 1 (same transaction):
SELECT salary FROM lab.employees WHERE id = 1; -- still sees old value (RR)
COMMIT;

-- Repeat with READ COMMITTED: Session 1 sees new value after Session 2 commits

-- Undo log monitoring
SHOW STATUS LIKE 'Innodb_purge%';
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
  WHERE NAME LIKE '%trx_undo%' OR NAME LIKE '%purge%';
```

**Read**:
- [InnoDB Multi-Versioning](https://dev.mysql.com/doc/refman/8.4/en/innodb-multi-versioning.html)
- [InnoDB Transaction Model](https://dev.mysql.com/doc/refman/8.4/en/innodb-transaction-model.html)
- *High Performance MySQL* Ch.6 — Transactions

**Deliverable**: Demo 2 sessions showing different behavior between RR and RC. Explain the read view visibility rules with a concrete example.

---

## 2.4 Locking

**Goal**: Understand InnoDB's row-level locking mechanism and deadlock handling.

**Prerequisites**: 2.3 (Transaction & MVCC) — locks enforce isolation for writers.

**Key Concepts**:
- **Record lock**: locks a single index record
- **Gap lock**: locks the gap between two index records (prevents phantom reads in RR)
- **Next-key lock** = record lock + gap lock on the gap before the record (default in RR)
- **Intention locks** (IS, IX): table-level indicators that a transaction intends to acquire row locks
- **Insert intention lock**: special gap lock that allows concurrent inserts into different positions in the same gap
- **Deadlock detection**: InnoDB maintains a wait-for graph; when a cycle is detected, the smaller transaction is rolled back
- **RC vs RR**: RC uses only record locks (no gap locks), RR uses next-key locks

**Lab**:
```sql
-- See current locks
SELECT * FROM performance_schema.data_locks\G
SELECT * FROM performance_schema.data_lock_waits\G

-- Experiment: Gap lock in RR
-- Session 1:
START TRANSACTION;
SELECT * FROM lab.employees WHERE department = 'Engineering' FOR UPDATE;

-- Session 2 (will be blocked if inserting into the gap):
INSERT INTO lab.employees (name, department, salary, hire_date)
  VALUES ('Test', 'Engineering', 50000, '2024-01-01');
-- Check data_lock_waits to see the blocking

-- Session 1:
ROLLBACK;

-- Experiment: Create a deadlock
-- Session 1:
START TRANSACTION;
UPDATE lab.employees SET salary = salary + 100 WHERE id = 1;

-- Session 2:
START TRANSACTION;
UPDATE lab.employees SET salary = salary + 100 WHERE id = 2;

-- Session 1:
UPDATE lab.employees SET salary = salary + 100 WHERE id = 2; -- waits

-- Session 2:
UPDATE lab.employees SET salary = salary + 100 WHERE id = 1; -- DEADLOCK!

-- Analyze deadlock
SHOW ENGINE INNODB STATUS\G
-- Look for "LATEST DETECTED DEADLOCK" section
```

**Read**:
- [InnoDB Locking](https://dev.mysql.com/doc/refman/8.4/en/innodb-locking.html)
- [InnoDB Deadlocks](https://dev.mysql.com/doc/refman/8.4/en/innodb-deadlocks.html)
- *High Performance MySQL* Ch.6 — Lock Types

**Deliverable**: Create 3 different deadlock scenarios. For each, show the `data_locks` output and explain why the deadlock occurred.

---

## 2.5 Redo Log & WAL

**Goal**: Understand how InnoDB guarantees durability and crash recovery.

**Prerequisites**: 2.1 (buffer pool) — dirty pages are the link between redo log and disk.

**Key Concepts**:
- **WAL (Write-Ahead Logging)**: changes are written to redo log BEFORE dirty pages are flushed to disk
- **Redo log**: circular buffer of fixed size. Records physical changes to data pages
- **LSN (Log Sequence Number)**: monotonically increasing counter tracking redo log position
- **Checkpoint**: the LSN up to which all dirty pages have been flushed. Redo log space before checkpoint can be reused
- **Doublewrite buffer**: pages are written to doublewrite area first, then to actual location. Protects against torn pages (partial writes during crash)
- **Crash recovery flow**: redo (apply committed changes) → undo (rollback uncommitted transactions)
- `innodb_flush_log_at_trx_commit`: 1 = flush every commit (safest), 2 = flush to OS cache, 0 = flush every second

**Lab**:
```sql
-- Redo log configuration (MySQL 8.0.30+ dynamic resizing)
SHOW VARIABLES LIKE 'innodb_redo_log_capacity';
SHOW VARIABLES LIKE 'innodb_log_buffer_size';
SHOW VARIABLES LIKE 'innodb_flush_log_at_trx_commit';

-- LSN and checkpoint monitoring
SHOW ENGINE INNODB STATUS\G
-- Look for "LOG" section: Log sequence number, Log flushed up to, Last checkpoint at

-- Redo log metrics
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
  WHERE NAME LIKE '%log%' AND STATUS = 'enabled';

-- Doublewrite buffer stats
SHOW STATUS LIKE 'Innodb_dblwr%';

-- Simulate: observe redo log activity during heavy writes
START TRANSACTION;
UPDATE lab.employees SET salary = salary + 1;
-- Check LSN change in INNODB STATUS before commit
COMMIT;
```

```bash
# Redo log files (MySQL 8.0.30+: #innodb_redo directory)
docker exec mysql-lab ls -lh /var/lib/mysql/#innodb_redo/
```

**Read**:
- [InnoDB Redo Log](https://dev.mysql.com/doc/refman/8.4/en/innodb-redo-log.html)
- [InnoDB Doublewrite Buffer](https://dev.mysql.com/doc/refman/8.4/en/innodb-doublewrite-buffer.html)
- *High Performance MySQL* Ch.4 — InnoDB Crash Recovery

**Deliverable**: Explain the crash recovery flow step by step: what happens from the moment `mysqld` starts after an unexpected crash. When is the doublewrite buffer needed?

---

## How It All Fits Together

```
Client writes data
  → Buffer Pool (2.1): page loaded into memory, modified → dirty page
  → Redo Log (2.5): WAL writes change to redo log FIRST → durability
  → B+ Tree (2.2): data organized in clustered index pages
  → MVCC (2.3): undo log keeps old versions → readers never blocked
  → Locking (2.4): row/gap locks enforce isolation between writers
  → Checkpoint: dirty pages flushed to disk, redo log space reclaimed
  → Crash: redo log replays committed changes, undo log rolls back uncommitted
```

---

## Progress Tracker

| # | Topic | Status |
|---|-------|--------|
| 2.1 | Buffer Pool | [ ] |
| 2.2 | B+ Tree Index | [ ] |
| 2.3 | Transaction & MVCC | [ ] |
| 2.4 | Locking | [ ] |
| 2.5 | Redo Log & WAL | [ ] |
