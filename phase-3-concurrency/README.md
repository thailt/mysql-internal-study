# Phase 3: The Concurrency Problem — Transactions & Isolation (Week 6–7)

> *Multiple users reading and writing the same data simultaneously. How do we keep everyone correct without killing performance?*

## Why This Phase?

Phase 2 showed how InnoDB stores and recovers data for a *single* user. But databases serve *thousands* of concurrent users. The moment two transactions touch the same row, everything breaks — unless we have rules.

Phase 3 = the rules. Isolation levels define correctness. Locks enforce writer safety. MVCC gives readers freedom. The transaction lifecycle ties it all together.

## Topic Map

```
┌─────────────────────────────────────────────────────┐
│         3.1 Isolation Levels                         │
│   (dirty reads, phantoms, the 4-level spectrum)      │
├──────────────────────┬──────────────────────────────┤
│ 3.2 Locking          │ 3.3 MVCC                      │
│ (record, gap,        │ (undo version chain,           │
│  next-key, deadlock) │  read view, purge thread)      │
├──────────────────────┴──────────────────────────────┤
│         3.4 Transaction Lifecycle                    │
│   (write path, read path, rollback, autocommit)      │
└─────────────────────────────────────────────────────┘
```

---

## The Constraint Chain

```
Multiple users access same data
  → Without rules → dirty reads, lost updates, phantoms
  → Isolation levels define the correctness/performance trade-off
  → Writers conflict → Locking (record, gap, next-key)
    → Circular wait → Deadlock detection (wait-for graph)
  → Readers blocked by locks → throughput collapses
    → MVCC: keep old row versions, readers never block
      → Old versions → Undo Log (rollback segments)
      → Which version visible? → Read View + visibility rules
      → Undo accumulates → Purge Thread
```

Every mechanism in this phase exists because the previous solution introduced a new problem. Isolation levels define the target. Locks protect writers. MVCC frees readers. The transaction lifecycle orchestrates all of it.

---

## 3.1 Isolation Levels & The Concurrency Spectrum

**Goal**: Understand the four SQL isolation levels and which concurrency anomalies each prevents.

**Why?** Without isolation, concurrent transactions cause chaos:
- **Dirty read**: Transaction A sees uncommitted data from Transaction B. If B rolls back, A acted on data that never existed.
- **Non-repeatable read**: Transaction A reads a row, B modifies and commits it, A reads again and gets a different result.
- **Phantom read**: Transaction A queries a range, B inserts a new row in that range and commits, A queries again and sees a new row appear.

Each isolation level is a trade-off: more isolation = more locking = less concurrency.

**Key Concepts**:
- **ACID** ties directly to InnoDB internals: **Atomicity** = undo log, **Consistency** = constraints + application logic, **Isolation** = MVCC + locks, **Durability** = redo log
- **READ UNCOMMITTED**: no protection. Reads see uncommitted modifications. Almost never used in production
- **READ COMMITTED (RC)**: no dirty reads. Each **statement** gets a fresh **read view** (snapshot). Sees committed data as of statement start. Used by Oracle, PostgreSQL default
- **REPEATABLE READ (RR)**: no dirty reads, no non-repeatable reads. A single **read view** is created at the **first read** in the transaction and reused for all subsequent reads. **InnoDB default**. In InnoDB, RR also prevents most phantom reads via gap locking
- **SERIALIZABLE**: all reads implicitly acquire `LOCK IN SHARE MODE`. Fully serialized but worst throughput
- `SET TRANSACTION ISOLATION LEVEL` changes the level for the next transaction. `SET SESSION` changes it for the session

**Lab**:
```sql
-- Check current isolation level
SELECT @@transaction_isolation;
SELECT @@global.transaction_isolation;

-- === Demo: Dirty Read (READ UNCOMMITTED) ===

-- Session 1:
SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
START TRANSACTION;
SELECT salary FROM lab.employees WHERE id = 1;

-- Session 2:
START TRANSACTION;
UPDATE lab.employees SET salary = 999999 WHERE id = 1;
-- DO NOT COMMIT

-- Session 1:
SELECT salary FROM lab.employees WHERE id = 1;
-- Sees 999999 (uncommitted data = dirty read!)

-- Session 2:
ROLLBACK;

-- Session 1:
SELECT salary FROM lab.employees WHERE id = 1;
-- Back to original value. Session 1 acted on phantom data.
COMMIT;

-- === Demo: Non-repeatable Read (RC vs RR) ===

-- Session 1 (RC):
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SELECT salary FROM lab.employees WHERE id = 1; -- e.g., 70000

-- Session 2:
UPDATE lab.employees SET salary = 80000 WHERE id = 1;
COMMIT;

-- Session 1:
SELECT salary FROM lab.employees WHERE id = 1;
-- Sees 80000 (non-repeatable read in RC!)
COMMIT;

-- Session 1 (RR):
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT salary FROM lab.employees WHERE id = 1; -- snapshot taken: 80000

-- Session 2:
UPDATE lab.employees SET salary = 90000 WHERE id = 1;
COMMIT;

-- Session 1:
SELECT salary FROM lab.employees WHERE id = 1;
-- Still sees 80000 (repeatable read — snapshot is stable)
COMMIT;
```

**Read**:
- [InnoDB Transaction Isolation Levels](https://dev.mysql.com/doc/refman/8.4/en/innodb-transaction-isolation-levels.html)
- *High Performance MySQL* Ch.1 — Transaction Isolation Levels
- [SQL Standard Isolation Levels](https://en.wikipedia.org/wiki/Isolation_(database_systems))

**Deliverable**: Create a table showing which anomalies each isolation level prevents/allows. Include the InnoDB-specific behavior (RR prevents most phantoms via gap locks).

---

## 3.2 Locking — Writer Safety

**Goal**: Understand InnoDB's lock types and how they serialize conflicting writes.

**Why?** Two writers modifying the same row simultaneously → data corruption. Locks serialize conflicting writes so only one transaction modifies a row at a time. But locking is expensive — the wrong granularity kills throughput.

**Key Concepts**:
- **Record lock**: locks a single index record. The most granular lock
- **Gap lock**: locks the gap *between* two index records. Prevents inserts into the gap. Only used in **RR** and **SERIALIZABLE** — prevents phantom reads
- **Next-key lock** = record lock + gap lock on the gap before the record. The default locking mode in **RR**. Locks the record AND the gap before it
- **Intention locks** (IS/IX): table-level indicators. A transaction acquiring a row-level S lock first acquires IS on the table. Allows InnoDB to quickly check for table-level conflicts without scanning every row lock
- **Insert intention lock**: a special gap lock that allows concurrent inserts at *different* positions within the same gap. Two inserts into positions 4 and 7 within gap (3, 10) do not block each other
- **RC vs RR locking**: RC uses only record locks (no gap locks) → better concurrency but phantom reads possible. RR uses next-key locks → prevents phantoms but more blocking
- **Deadlock**: two or more transactions each hold a lock the other needs. InnoDB detects cycles in the **wait-for graph** and rolls back the transaction with the fewest undo log entries (smallest cost)
- `innodb_deadlock_detect` (ON by default): enables proactive deadlock detection. Disabling it relies on `innodb_lock_wait_timeout` instead
- `innodb_lock_wait_timeout` (default 50s): how long a transaction waits for a lock before giving up

**Lab**:
```sql
-- === Observe locks in real time ===
SELECT * FROM performance_schema.data_locks\G
SELECT * FROM performance_schema.data_lock_waits\G

-- === Experiment: Gap Lock in RR ===

-- Setup: ensure we have a known state
SELECT id, department FROM lab.employees WHERE department = 'Engineering' ORDER BY id;

-- Session 1:
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT * FROM lab.employees WHERE department = 'Engineering' FOR UPDATE;

-- Check what locks were acquired:
SELECT ENGINE_LOCK_TYPE, LOCK_MODE, LOCK_TYPE, LOCK_DATA
  FROM performance_schema.data_locks
  WHERE OBJECT_SCHEMA = 'lab' AND OBJECT_NAME = 'employees';

-- Session 2 (will block — gap lock prevents insert):
INSERT INTO lab.employees (name, department, salary, hire_date)
  VALUES ('Gap Test', 'Engineering', 50000, '2024-01-01');

-- Check the wait:
SELECT * FROM performance_schema.data_lock_waits\G

-- Session 1:
ROLLBACK;
-- Session 2 now proceeds (delete the test row if inserted)

-- === Experiment: Deadlock Creation ===

-- Session 1:
START TRANSACTION;
UPDATE lab.employees SET salary = salary + 100 WHERE id = 1;

-- Session 2:
START TRANSACTION;
UPDATE lab.employees SET salary = salary + 100 WHERE id = 2;

-- Session 1 (will wait for Session 2's lock on id=2):
UPDATE lab.employees SET salary = salary + 100 WHERE id = 2;

-- Session 2 (deadlock detected — one session gets error 1213):
UPDATE lab.employees SET salary = salary + 100 WHERE id = 1;

-- Analyze the deadlock:
SHOW ENGINE INNODB STATUS\G
-- Look for "LATEST DETECTED DEADLOCK" section

-- Clean up:
-- (whichever session survived) ROLLBACK;

-- === Deadlock Scenario 2: Index-order deadlock ===

-- Session 1:
START TRANSACTION;
SELECT * FROM lab.employees WHERE id = 10 FOR UPDATE;

-- Session 2:
START TRANSACTION;
SELECT * FROM lab.employees WHERE id = 20 FOR UPDATE;

-- Session 1:
SELECT * FROM lab.employees WHERE id = 20 FOR UPDATE; -- waits

-- Session 2:
SELECT * FROM lab.employees WHERE id = 10 FOR UPDATE; -- DEADLOCK

-- === Deadlock Scenario 3: Gap lock deadlock ===

-- Session 1:
START TRANSACTION;
SELECT * FROM lab.employees WHERE id BETWEEN 5 AND 8 FOR UPDATE;

-- Session 2:
START TRANSACTION;
SELECT * FROM lab.employees WHERE id BETWEEN 12 AND 15 FOR UPDATE;

-- Both sessions now try to INSERT into each other's gap range:
-- Session 1:
INSERT INTO lab.employees (id, name, department, salary, hire_date)
  VALUES (13, 'Deadlock3a', 'Test', 50000, '2024-01-01');

-- Session 2:
INSERT INTO lab.employees (id, name, department, salary, hire_date)
  VALUES (6, 'Deadlock3b', 'Test', 50000, '2024-01-01');
-- DEADLOCK
```

**Read**:
- [InnoDB Locking](https://dev.mysql.com/doc/refman/8.4/en/innodb-locking.html)
- [InnoDB Deadlocks](https://dev.mysql.com/doc/refman/8.4/en/innodb-deadlocks.html)
- [Locks Set by Different SQL Statements](https://dev.mysql.com/doc/refman/8.4/en/innodb-locks-set.html)
- *High Performance MySQL* Ch.6 — Lock Types

**Deliverable**: Create 3 deadlock scenarios (different root causes). For each, show the `data_locks` output and explain the wait-for graph that caused the cycle.

---

## 3.3 MVCC — Reader Freedom

**Goal**: Understand how InnoDB lets readers see consistent data without acquiring locks.

**Why?** If readers also need locks, throughput collapses — readers block writers, writers block readers. With MVCC, readers see a *consistent snapshot* without any locks. Writers proceed independently. This is what makes InnoDB viable for high-concurrency OLTP.

**Key Concepts**:
- **Undo log** stores old row versions in **rollback segments**. Each modification creates a new version; the old version is written to the undo log. Multiple versions form a **version chain** per row (linked list from newest to oldest)
- **Hidden columns** on every InnoDB row:
  - **DB_TRX_ID** (6 bytes): transaction ID of the last transaction that modified the row
  - **DB_ROLL_PTR** (7 bytes): pointer to the previous version in the undo log
  - **DB_ROW_ID** (6 bytes): auto-incrementing row ID (only if no user-defined PK)
- **Read view** = snapshot of active transaction IDs, created at:
  - **RR**: first read in the transaction (reused for all subsequent reads)
  - **RC**: each individual statement (fresh view per statement)
- **Visibility rules** — a row version is visible to my read view if:
  - `trx_id < m_up_limit_id` (committed before the oldest active transaction) → **visible**
  - `trx_id >= m_low_limit_id` (started after my snapshot was taken) → **not visible**
  - `trx_id` is in the active list (`m_ids`) → **not visible** (still in-progress)
  - `trx_id == my_trx_id` → **visible** (my own changes)
  - If not visible → follow **DB_ROLL_PTR** to the previous version → check again
- **Purge thread**: background thread that cleans up undo log entries no longer needed by any active read view. If no transaction needs the old version, it's safe to delete
- **Long-running transactions** prevent purge → undo log grows → history list length increases → performance degrades. Monitor `trx_rseg_history_len`

**Lab**:
```sql
-- === RR vs RC: Same experiment, different visibility ===

-- Session 1 (RR):
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT salary FROM lab.employees WHERE id = 1; -- e.g., 70000 (read view created)

-- Session 2:
UPDATE lab.employees SET salary = 75000 WHERE id = 1;
COMMIT;

-- Session 3:
UPDATE lab.employees SET salary = 80000 WHERE id = 1;
COMMIT;

-- Session 1:
SELECT salary FROM lab.employees WHERE id = 1;
-- Still sees 70000! (RR read view from first read)
COMMIT;

-- Session 1 (RC):
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SELECT salary FROM lab.employees WHERE id = 1; -- 80000

-- Session 2:
UPDATE lab.employees SET salary = 85000 WHERE id = 1;
COMMIT;

-- Session 1:
SELECT salary FROM lab.employees WHERE id = 1;
-- Sees 85000 (RC creates fresh read view per statement)
COMMIT;

-- === Monitor active transactions and undo ===
SELECT trx_id, trx_state, trx_started, trx_rows_modified, trx_isolation_level
  FROM information_schema.INNODB_TRX\G

-- Undo log / history list length
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
  WHERE NAME IN (
    'trx_rseg_history_len',
    'trx_undo_slots_used',
    'trx_undo_slots_cached',
    'trx_rseg_current_size'
  );

-- Purge thread stats
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
  WHERE NAME LIKE '%purge%';

SHOW STATUS LIKE 'Innodb_purge%';

-- === Observe the cost of long transactions ===
-- Session 1: start a long-running transaction
START TRANSACTION;
SELECT * FROM lab.employees LIMIT 1; -- creates read view

-- Session 2: generate many updates
-- (run a loop or UPDATE many rows, commit)

-- Watch history list grow because Session 1's read view prevents purge:
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
  WHERE NAME = 'trx_rseg_history_len';
```

**Read**:
- [InnoDB Multi-Versioning](https://dev.mysql.com/doc/refman/8.4/en/innodb-multi-versioning.html)
- [InnoDB Undo Logs](https://dev.mysql.com/doc/refman/8.4/en/innodb-undo-logs.html)
- *High Performance MySQL* Ch.6 — Multi-Version Concurrency Control
- Jeremy Cole: [InnoDB MVCC internals](https://blog.jcole.us/innodb/)

**Deliverable**: Demo RR vs RC with a concrete example (3 sessions, 2 updates). Draw the undo version chain for a row modified by 3 transactions, showing DB_TRX_ID, DB_ROLL_PTR, and which version each read view sees.

---

## 3.4 Transaction Lifecycle — Putting It Together

**Goal**: Trace the complete lifecycle of a transaction through every InnoDB component.

**Why?** Understanding individual mechanisms isn't enough. In production you debug *transactions*, not abstract components. You need to see the complete flow: which component fires when, what happens at COMMIT, what happens at ROLLBACK, where the bottlenecks are.

**Key Concepts**:
- **Write path**:
  ```
  BEGIN
    → Acquire locks (record/gap/next-key as needed)
    → Modify page in buffer pool (page becomes dirty)
    → Write old version to undo log (for rollback + MVCC)
    → Write change to redo log buffer
  COMMIT
    → Flush redo log to disk (durability guarantee)
    → Release all locks
    → Dirty page flushed later by page cleaner (async)
  ```
- **Read path**:
  ```
  SELECT
    → Check read view (created at first read for RR, per statement for RC)
    → Read current row version from buffer pool / disk
    → If DB_TRX_ID not visible → follow DB_ROLL_PTR
    → Walk undo version chain → return first visible version
  ```
- **Rollback**: apply undo log entries in reverse order → restore each modified row to its pre-transaction state → release all locks
- **Autocommit** (`autocommit=ON`, default): each individual statement is an implicit transaction (BEGIN + statement + COMMIT). Explicit `START TRANSACTION` disables autocommit for that transaction
- **Long transaction dangers**:
  - **Lock holding**: other transactions wait → cascading timeouts
  - **Undo log bloat**: prevents purge → history list grows → performance degrades
  - **Replication lag**: large transactions generate huge binlog events → replicas fall behind
  - **Buffer pool pollution**: undo pages stay in buffer pool → evict useful data pages
- **Savepoints**: `SAVEPOINT name` / `ROLLBACK TO name` — partial rollback within a transaction

**Lab**:
```sql
-- === Full transaction lifecycle observation ===

-- Terminal 1: Monitor (keep running between steps)
SELECT trx_id, trx_state, trx_started, trx_rows_locked, trx_rows_modified,
       trx_isolation_level, trx_is_read_only
  FROM information_schema.INNODB_TRX\G

-- Terminal 2: Run a write transaction step by step
START TRANSACTION;

-- Check: transaction should now appear in INNODB_TRX
-- (run Terminal 1 query)

-- Step 1: First write — locks acquired, undo/redo generated
UPDATE lab.employees SET salary = salary + 500 WHERE id = 1;

-- Check locks:
SELECT ENGINE_LOCK_TYPE, LOCK_MODE, LOCK_TYPE, LOCK_DATA
  FROM performance_schema.data_locks
  WHERE LOCK_STATUS = 'GRANTED';

-- Check trx_rows_modified and trx_rows_locked in INNODB_TRX
-- (run Terminal 1 query)

-- Step 2: More writes — undo log grows
UPDATE lab.employees SET salary = salary + 500 WHERE id = 2;
UPDATE lab.employees SET salary = salary + 500 WHERE id = 3;

-- Check undo growth:
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
  WHERE NAME = 'trx_rseg_history_len';

-- Step 3: COMMIT — redo flushed, locks released
COMMIT;

-- Verify: locks gone, transaction gone from INNODB_TRX
SELECT * FROM performance_schema.data_locks
  WHERE OBJECT_SCHEMA = 'lab';
SELECT * FROM information_schema.INNODB_TRX;

-- === Observe lock acquisition and release timing ===

-- Session 1:
START TRANSACTION;
UPDATE lab.employees SET salary = salary + 100 WHERE id = 1;
-- Lock held from now until COMMIT/ROLLBACK

-- Session 2:
START TRANSACTION;
UPDATE lab.employees SET salary = salary + 100 WHERE id = 1;
-- Blocked! Waiting for Session 1's lock.

-- Session 1:
COMMIT; -- Lock released → Session 2 proceeds immediately

-- Session 2:
COMMIT;

-- === Undo growth during long transaction ===

-- Baseline:
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
  WHERE NAME = 'trx_rseg_history_len';

-- Session 1: Long-running read transaction
START TRANSACTION;
SELECT COUNT(*) FROM lab.employees; -- creates read view

-- Session 2: Generate churn
-- (run multiple updates and commits)
UPDATE lab.employees SET salary = salary + 1;
-- ... repeat several times with COMMIT between each

-- Watch history list grow (Session 1's read view blocks purge):
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
  WHERE NAME = 'trx_rseg_history_len';

-- Session 1:
COMMIT; -- read view released → purge can proceed

-- Watch history list shrink:
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
  WHERE NAME = 'trx_rseg_history_len';

-- === Savepoint demo ===
START TRANSACTION;
UPDATE lab.employees SET salary = 50000 WHERE id = 1;
SAVEPOINT before_big_change;
UPDATE lab.employees SET salary = 0 WHERE id = 1;
-- Oops, wrong value:
ROLLBACK TO before_big_change;
-- salary for id=1 is back to 50000 (within this transaction)
COMMIT;
```

**Read**:
- [InnoDB Transaction Model](https://dev.mysql.com/doc/refman/8.4/en/innodb-transaction-model.html)
- [SAVEPOINT Syntax](https://dev.mysql.com/doc/refman/8.4/en/savepoint.html)
- [Autocommit, Commit, and Rollback](https://dev.mysql.com/doc/refman/8.4/en/innodb-autocommit-commit-rollback.html)
- *High Performance MySQL* Ch.6 — Transactions

**Deliverable**: Draw the complete transaction lifecycle diagram showing the write path, read path, and rollback path. Annotate which InnoDB components (buffer pool, undo log, redo log, lock manager, purge thread, page cleaner) are involved at each step.

---

## How It All Fits Together

```
Concurrent transactions arrive
  → Isolation Level (3.1): defines which anomalies are acceptable
  → Writer hits a row:
      → Lock Manager (3.2): acquire record/gap/next-key lock
      → Modify page in buffer pool → dirty page
      → Write old version to undo log (for MVCC + rollback)
      → Write change to redo log (durability)
  → Reader hits a row:
      → MVCC (3.3): check read view → walk undo version chain if needed
      → No locks acquired → readers never block writers
  → COMMIT (3.4): flush redo → release locks → dirty page flushed later
  → ROLLBACK (3.4): apply undo entries in reverse → release locks
  → Purge Thread: clean undo entries no longer visible to any read view
```

Phase 2 built the storage foundation (buffer pool, B+ Tree, redo/undo). Phase 3 showed how InnoDB uses those foundations to handle *concurrency*: isolation levels set the rules, locks protect writers, MVCC frees readers, and the transaction lifecycle orchestrates everything.

**What's next?** Phase 4 zooms into **query performance**: *how* does the optimizer choose between index scan and full scan? *why* do some JOINs crawl while others fly? *what* makes a covering index fast? All derived from one constraint: **the optimizer must find the cheapest execution plan**.

---

## Progress Tracker

| # | Topic | Status |
|---|-------|--------|
| 3.1 | Isolation Levels & The Concurrency Spectrum | [ ] |
| 3.2 | Locking — Writer Safety | [ ] |
| 3.3 | MVCC — Reader Freedom | [ ] |
| 3.4 | Transaction Lifecycle — Putting It Together | [ ] |
