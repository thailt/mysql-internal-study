# Phase 5: The Scale Problem — Replication, HA & Production (Week 10+)

> *A single server has limits in capacity, availability, and observability. How do we go beyond?*

A single MySQL instance can only handle so much traffic, has a single point of failure, and gives limited visibility into what's going wrong. This phase addresses the three forces that push you beyond a single server: **sharing changes** (binary log & replication), **surviving failure** (high availability), and **seeing what's happening** (observability).

## First Principle (Nguyên lý 6)

**Mở rộng và sẵn sàng** — Một server có giới hạn; cần chia sẻ thay đổi, sống sót khi chết, phục hồi sai lỗi, và đo đạc.

- **Hỏi trước khi đọc:** Làm sao replica biết "chỗ nào" để đồng bộ? Redo log và binlog phải nhất quán thế nào? Server chết, replica lag 2s — failover xong mất tối đa bao nhiêu commit? Backup + PITR cần những gì?
- **Ánh xạ:** [first-principles-learning.md](../first-principles-learning.md) → Nguyên lý 6. Topics 5.1–5.4 = binlog, replication/HA, backup/PITR, observability.

## Why This Phase?

Every previous phase assumed a single mysqld instance. In production, that's rarely enough. You need to replicate data for read scaling and failover, recover from disasters, and diagnose problems systematically. All of these capabilities are built on top of the internals you already understand — redo log, buffer pool, transactions, locking, and query execution.

Phase 5 = taking the single-server mastery from Phases 1–4 and extending it to the real world.

## Constraint Chain

```
Single server limits
  → Need to share changes to other servers → Binary Log
    → Deterministic replication → Row-Based Replication
    → Redo log + binlog must agree → Two-Phase Commit (XA)
  → Server dies → need failover
    → Async replication (fast, risk data loss)
    → Semi-sync (safer, higher latency)
    → Group Replication (Paxos consensus, automatic failover)
  → Data corruption / human error → Backup + PITR
  → Can't fix what you can't see → Observability
```

## Topic Map

```
┌─────────────────────────────────────────────────────────┐
│               5.1 Binary Log & Change Propagation        │
│  (binlog formats, GTID, two-phase commit, event types)   │
├─────────────────────────────────────────────────────────┤
│               5.2 Replication & High Availability        │
│  (async, semi-sync, parallel apply, Group Replication)   │
├──────────────────────┬──────────────────────────────────┤
│ 5.3 Backup &         │ 5.4 Observability &               │
│ Recovery             │ Troubleshooting                    │
│ (mysqldump, CLONE,   │ (Performance Schema, sys schema,   │
│  XtraBackup, PITR)   │  memory/I/O tuning, health check)  │
└──────────────────────┴──────────────────────────────────┘
```

---

## 5.1 Binary Log & Change Propagation

**Goal**: Understand MySQL's binary log as the foundation for replication and point-in-time recovery.

**Why?** To replicate or recover, other servers need to know what changed. The binary log is the ordered record of all data changes — every INSERT, UPDATE, DELETE is captured as a sequence of events. Without it, there is no replication, no PITR, no change propagation.

**Key Concepts**:
- **Binary log (binlog)**: ordered sequence of **events** describing data changes. Foundation for replication and PITR
- **Formats**:
  - **Statement-based replication (SBR)**: logs the SQL statement. Compact but **non-deterministic** — functions like `NOW()`, `UUID()`, `RAND()` can cause source/replica divergence
  - **Row-based replication (RBR)**: logs actual **before/after row images**. Deterministic, larger size. Default since **5.7.7**
  - **Mixed**: server chooses SBR when safe, falls back to RBR for non-deterministic statements
- **`binlog_row_image=FULL`** (default): logs all columns in before/after images. `MINIMAL` logs only changed columns + PK (saves space, harder to debug)
- **GTID (Global Transaction Identifier)**: format `server_uuid:transaction_id`. Enables **auto-positioning** — a replica knows exactly which transactions it has and which it needs, eliminating manual binlog file/position tracking
- **Binlog event sequence** for a row change:
  ```
  Anonymous_Gtid (or Gtid) → Query(BEGIN) → Table_map → Write_rows / Update_rows / Delete_rows → Xid(COMMIT)
  ```
- **Two-phase commit (internal XA)**: ensures redo log and binlog agree on which transactions committed
  1. **InnoDB prepare**: transaction marked as prepared in redo log
  2. **Binlog write**: events written and fsynced to binlog
  3. **InnoDB commit**: transaction marked as committed in redo log
  - **Xid** (transaction ID) links the redo log entry to the binlog entry. During crash recovery, MySQL checks: if Xid exists in binlog → commit in InnoDB; if not → rollback
- **Rotation**: new binlog file created when current file reaches **`max_binlog_size`** (default 1GB) or on `FLUSH BINARY LOGS`
- **Purging**: `PURGE BINARY LOGS BEFORE '2024-01-01'` or automatic via **`binlog_expire_logs_seconds`** (default 2592000 = 30 days)

**Lab**:
```sql
-- Binary log configuration
SHOW VARIABLES LIKE 'log_bin%';
SHOW VARIABLES LIKE 'binlog_format';
SHOW VARIABLES LIKE 'binlog_row_image';
SHOW VARIABLES LIKE 'gtid_mode';
SHOW VARIABLES LIKE 'enforce_gtid_consistency';
SHOW VARIABLES LIKE 'max_binlog_size';
SHOW VARIABLES LIKE 'binlog_expire_logs_seconds';

-- List binlog files and current position
SHOW BINARY LOGS;
SHOW BINARY LOG STATUS;

-- Make changes and observe events
INSERT INTO lab.employees (name, department, salary, hire_date)
  VALUES ('Binlog Demo', 'QA', 65000, '2025-03-01');
UPDATE lab.employees SET salary = 70000 WHERE name = 'Binlog Demo';
DELETE FROM lab.employees WHERE name = 'Binlog Demo';

-- View the binlog events generated
SHOW BINLOG EVENTS IN 'binlog.000001' LIMIT 50;

-- GTID tracking
SELECT @@gtid_executed\G
SELECT @@gtid_purged\G
```

```bash
# Decode binlog to human-readable format with row images
docker exec mysql-lab mysqlbinlog --base64-output=DECODE-ROWS -v \
  /var/lib/mysql/binlog.000001 | tail -80

# Binlog file sizes on disk
docker exec mysql-lab ls -lh /var/lib/mysql/binlog.*
```

**Read**:
- [Binary Log Overview](https://dev.mysql.com/doc/refman/8.4/en/binary-log.html)
- [GTID Concepts](https://dev.mysql.com/doc/refman/8.4/en/replication-gtids-concepts.html)
- [Binary Log Formats](https://dev.mysql.com/doc/refman/8.4/en/replication-sbr-rbr.html)
- *High Performance MySQL* Ch.10 — Replication

**Deliverable**: Decode a binlog file using `mysqlbinlog --base64-output=DECODE-ROWS -v`. Identify each event type (Gtid, Query, Table_map, Write_rows, Update_rows, Delete_rows, Xid). Explain the two-phase commit flow: what happens if a crash occurs between InnoDB prepare and binlog write? Between binlog write and InnoDB commit?

---

## 5.2 Replication & High Availability

**Goal**: Understand how MySQL replicates data between servers and the trade-offs across replication modes.

**Why?** A single point of failure means downtime. Replication provides read scaling (spread SELECT load) and failover capability (promote a replica when the source dies). The key engineering trade-off: **speed vs safety** — faster replication risks data loss, safer replication adds latency.

**Prerequisites**: 5.1 (Binary Log) — replication is built on top of binlog events.

**Key Concepts**:
- **Async replication** (default): three-thread architecture
  - **Source dump thread**: reads binlog and sends events to replica
  - **Replica IO thread**: receives events, writes them to **relay log** (local copy of source's binlog)
  - **Replica SQL thread**: reads relay log and applies events to replica's data
  - Risk: if source crashes before replica receives latest events → **data loss**
- **Semi-synchronous replication**: source waits for at least **1 replica ACK** before returning to client
  - **`AFTER_SYNC`** (lossless semi-sync, default in 8.0): source waits for replica ACK **after binlog write but before engine commit**. On failover, no phantom reads — uncommitted transactions on old source were never visible to clients
  - **`AFTER_COMMIT`**: source waits for ACK **after engine commit**. Faster, but on failover a client may have seen a committed transaction that the new primary doesn't have
  - Trade-off: increased latency (network round-trip) for stronger durability guarantee
- **Parallel replication** (`replica_parallel_workers`): applies non-conflicting transactions concurrently on the replica
  - **`LOGICAL_CLOCK`**: transactions that committed in the same binlog group on source can be applied in parallel
  - **`WRITESET`**: transactions with non-overlapping writesets (different PKs modified) can be applied in parallel — more parallelism than LOGICAL_CLOCK
- **Group Replication**: **Paxos-based consensus** — every transaction is certified by the group before commit
  - **Conflict detection**: based on **writesets** (primary keys modified). If two members modify the same row concurrently, the first to be certified wins, the second is rolled back
  - **Single-primary mode** (default): one read-write member, others read-only with automatic failover
  - **Multi-primary mode**: all members accept writes. Requires careful schema design (no foreign keys across different members' writes)
- **InnoDB Cluster** = Group Replication + **MySQL Shell** (`dba.createCluster()`) + **MySQL Router** (read/write splitting, automatic failover routing)
- **Consistency levels**: `EVENTUAL` (no guarantee, default), `BEFORE_ON_PRIMARY_FAILOVER` (new primary waits for backlog before serving reads), `BEFORE` (reads wait for preceding transactions to apply), `AFTER` (writes wait for all members to apply)
- **Quorum**: majority of members must be reachable. 3 nodes tolerate 1 failure, 5 tolerate 2, 7 tolerate 3

**Lab**:
```sql
-- Replication plugins available
SHOW PLUGINS WHERE Name LIKE '%semi%' OR Name LIKE '%group%';

-- Parallel replication config
SHOW VARIABLES LIKE 'replica_parallel%';
SHOW VARIABLES LIKE 'binlog_transaction_dependency_tracking';

-- Group Replication variables
SHOW VARIABLES LIKE 'group_replication%';

-- Check GR plugin status
SELECT PLUGIN_NAME, PLUGIN_STATUS FROM information_schema.PLUGINS
  WHERE PLUGIN_NAME LIKE 'group_replication';

-- Performance Schema replication tables
SELECT * FROM performance_schema.replication_connection_status\G
SELECT * FROM performance_schema.replication_applier_status\G
SELECT * FROM performance_schema.replication_group_members;
SELECT * FROM performance_schema.replication_group_member_stats\G

-- Consistency level
SHOW VARIABLES LIKE 'group_replication_consistency';
```

**Read**:
- [MySQL Replication](https://dev.mysql.com/doc/refman/8.4/en/replication.html)
- [Semi-Synchronous Replication](https://dev.mysql.com/doc/refman/8.4/en/replication-semisync.html)
- [Group Replication](https://dev.mysql.com/doc/refman/8.4/en/group-replication.html)
- [InnoDB Cluster](https://dev.mysql.com/doc/mysql-shell/8.4/en/mysql-innodb-cluster.html)
- *High Performance MySQL* Ch.10 — Replication Topologies

**Deliverable**: Draw the async replication data flow showing all 3 threads (dump thread, IO thread, SQL thread) and the data stores they interact with (binlog, relay log, data files). Explain: during a failover scenario, when does `AFTER_SYNC` prevent data inconsistency that `AFTER_COMMIT` would allow?

---

## 5.3 Backup & Recovery

**Goal**: Understand backup strategies, their trade-offs, and how to perform point-in-time recovery.

**Why?** Hardware fails, humans run `DROP TABLE` by accident, ransomware encrypts your data files. Backups are the last line of defense. Replication is **not** a backup — a `DROP TABLE` on the source replicates to all replicas instantly.

**Prerequisites**: 5.1 (Binary Log) — PITR depends on replaying binlog from the backup position.

**Key Concepts**:
- **Logical backup**: SQL-level dump (human-readable, portable, slow for large datasets)
  - **`mysqldump`**: single-threaded. **`--single-transaction`** starts a consistent snapshot using REPEATABLE READ for InnoDB tables (no locking). Without it, uses `FLUSH TABLES WITH READ LOCK` (blocks all writes)
  - **`mysql-shell util.dumpInstance()`**: parallel, compressed, chunk-based. Significantly faster for large databases
- **Physical backup**: file-level copy (fast, but tied to MySQL version and platform)
  - **Percona XtraBackup**: hot backup — copies InnoDB data files while recording redo log changes, then applies redo log during prepare phase. Supports **incremental** backups
  - **MySQL Enterprise Backup**: official Oracle tool, similar approach
- **CLONE plugin** (8.0.17+): physical snapshot from a running instance **over the network**. Ideal for provisioning new replicas — replaces the traditional snapshot+binlog approach
- **Point-in-time recovery (PITR)**:
  1. Restore the most recent **full backup**
  2. Identify the backup's **binlog position** (or GTID)
  3. Replay binlog events from that position to the target timestamp using `mysqlbinlog --stop-datetime`
- **Backup strategy**: **full weekly** + **incremental daily** + **continuous binlog archiving** to remote storage
- **`--single-transaction`** vs **`--lock-all-tables`**: InnoDB gets a consistent snapshot via MVCC (no locks); MyISAM requires a global read lock

**Lab**:
```sql
-- CLONE plugin
INSTALL PLUGIN clone SONAME 'mysql_clone.so';
SELECT PLUGIN_NAME, PLUGIN_STATUS FROM information_schema.PLUGINS
  WHERE PLUGIN_NAME = 'clone';

-- Check binlog position before backup (needed for PITR)
SHOW BINARY LOG STATUS;
```

```bash
# Logical backup with mysqldump (consistent InnoDB snapshot)
docker exec mysql-lab mysqldump -u root -prootpass \
  --single-transaction --routines --triggers --events \
  --source-data=2 \
  lab > /tmp/lab_backup.sql

# Inspect the dump header (contains binlog position)
head -30 /tmp/lab_backup.sql

# Backup specific tables
docker exec mysql-lab mysqldump -u root -prootpass \
  --single-transaction lab employees orders > /tmp/lab_tables.sql

# PITR workflow:
# 1. Restore full backup
# docker exec -i mysql-lab mysql -u root -prootpass lab < /tmp/lab_backup.sql

# 2. Find binlog events between backup and target time
# docker exec mysql-lab mysqlbinlog \
#   --start-datetime="2025-03-01 00:00:00" \
#   --stop-datetime="2025-03-08 12:00:00" \
#   /var/lib/mysql/binlog.000001

# 3. Apply binlog events up to target time
# docker exec mysql-lab mysqlbinlog \
#   --stop-datetime="2025-03-08 12:00:00" \
#   /var/lib/mysql/binlog.000001 | \
#   docker exec -i mysql-lab mysql -u root -prootpass
```

**Read**:
- [mysqldump](https://dev.mysql.com/doc/refman/8.4/en/mysqldump.html)
- [MySQL CLONE Plugin](https://dev.mysql.com/doc/refman/8.4/en/clone-plugin.html)
- [Point-in-Time Recovery](https://dev.mysql.com/doc/refman/8.4/en/point-in-time-recovery.html)
- [Percona XtraBackup](https://docs.percona.com/percona-xtrabackup/latest/)
- *High Performance MySQL* Ch.11 — Backup and Recovery

**Deliverable**: Perform a full backup + PITR exercise: (1) take a `mysqldump` with `--single-transaction`, (2) make several changes (INSERT, UPDATE, DELETE), (3) identify the target timestamp, (4) restore the backup, (5) replay the binlog to the target point. Document each step and the binlog position tracking.

---

## 5.4 Observability & Troubleshooting

**Goal**: Master MySQL's instrumentation and develop a systematic approach to diagnosing production issues.

**Why?** You can't fix what you can't see. Production problems are rarely obvious — they manifest as "the app is slow" and require systematic diagnosis across multiple dimensions: connections, queries, locks, I/O, memory, and replication. MySQL provides deep instrumentation; the skill is knowing where to look.

**Prerequisites**: All previous phases provide the conceptual foundation for understanding what the instrumentation is measuring.

**Key Concepts**:
- **Performance Schema**: in-memory instrumentation engine with zero disk I/O overhead
  - **Instruments**: named probes in the source code — `wait/io/file/innodb/innodb_data_file`, `statement/sql/select`, etc.
  - **Consumers**: tables that store collected events — `events_statements_history`, `events_waits_current`, etc.
  - **Event hierarchy**: transactions → statements → stages → waits (each level nests inside the level above)
  - **Digests**: normalized SQL patterns — groups queries by structure, ignoring literal values. Key for identifying problematic query patterns
- **sys schema**: human-readable views built on Performance Schema
  - **`statement_analysis`**: top queries by latency, rows examined, tmp tables
  - **`innodb_buffer_stats_by_table`**: buffer pool usage per table
  - **`schema_unused_indexes`**: indexes never used since last restart — candidates for removal
  - **`innodb_lock_waits`**: human-readable lock wait summary
  - **`memory_global_by_current_bytes`**: memory allocation by component
- **Memory architecture**:
  - **Global buffers** (shared): **buffer pool** (70-80% of RAM on dedicated servers), **log buffer** (`innodb_log_buffer_size`), **table cache** (`table_open_cache`)
  - **Session buffers** (per-connection, allocated on demand): **`sort_buffer_size`**, **`join_buffer_size`**, **`tmp_table_size`** / `max_heap_table_size`, `read_buffer_size`
  - Memory formula: `global_buffers + (max_connections × session_buffers)` = theoretical max
- **I/O tuning**:
  - **`innodb_io_capacity`**: normal background flushing rate. SSD = 1000–10000, HDD = 200
  - **`innodb_flush_method=O_DIRECT`**: bypass OS page cache, avoid double buffering (recommended for dedicated servers with buffer pool properly sized)
  - **Tablespace types**: system (`ibdata1`), file-per-table (`.ibd`), general, undo
- **Slow query log**: captures queries exceeding **`long_query_time`**. Analyze with **`mysqldumpslow`** or **`pt-query-digest`** (Percona Toolkit)
- **Lock contention**:
  - **`performance_schema.data_locks`**: current locks held
  - **`performance_schema.data_lock_waits`**: who is blocking whom
  - **`sys.innodb_lock_waits`**: human-readable summary with blocking/waiting queries
- **`SHOW ENGINE INNODB STATUS`** sections:
  - **SEMAPHORES**: mutex/rw-lock contention (spin waits, OS waits)
  - **TRANSACTIONS**: active transactions, undo log usage, lock info
  - **FILE I/O**: pending reads/writes, I/O helper threads
  - **BUFFER POOL AND MEMORY**: hit ratio, dirty pages, free pages, pages read/written
  - **LOG**: redo log LSN, checkpoint lag, log I/O
  - **ROW OPERATIONS**: reads, inserts, updates, deletes per second
- **Systematic diagnosis approach**: connections → slow queries → locks → I/O → buffer pool → replication

**Lab**:
```sql
-- Performance Schema: instruments and consumers
SHOW VARIABLES LIKE 'performance_schema';
SELECT NAME, ENABLED, TIMED FROM performance_schema.setup_instruments
  WHERE ENABLED = 'YES' LIMIT 20;
SELECT * FROM performance_schema.setup_consumers;

-- Top queries by total latency
SELECT * FROM sys.statement_analysis LIMIT 10;

-- Queries with full table scans
SELECT * FROM sys.statements_with_full_table_scans LIMIT 10;

-- Top waits: what is MySQL spending time on?
SELECT event_name, COUNT_STAR, SUM_TIMER_WAIT/1e12 AS total_wait_sec
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC LIMIT 15;

-- Statement digests: grouped query patterns
SELECT DIGEST_TEXT, COUNT_STAR, AVG_TIMER_WAIT/1e12 AS avg_sec,
       SUM_ROWS_EXAMINED, SUM_ROWS_SENT
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC LIMIT 10;

-- Memory usage
SELECT * FROM sys.memory_global_total;
SELECT * FROM sys.memory_global_by_current_bytes LIMIT 15;

-- Buffer pool configuration and stats
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SELECT
  (1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)) * 100 AS hit_ratio
FROM (
  SELECT VARIABLE_VALUE AS Innodb_buffer_pool_reads
  FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads'
) r, (
  SELECT VARIABLE_VALUE AS Innodb_buffer_pool_read_requests
  FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests'
) rr;

-- I/O capacity and flush method
SHOW VARIABLES LIKE 'innodb_io_capacity%';
SHOW VARIABLES LIKE 'innodb_flush_method';

-- I/O activity by file
SELECT * FROM sys.io_global_by_file_by_bytes LIMIT 15;

-- Unused indexes
SELECT * FROM sys.schema_unused_indexes WHERE object_schema = 'lab';

-- Slow query log setup
SHOW VARIABLES LIKE 'slow_query_log%';
SHOW VARIABLES LIKE 'long_query_time';
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 0.5;

-- Generate a slow query to test
SELECT * FROM lab.employees WHERE name LIKE '%test%';
SHOW GLOBAL STATUS LIKE 'Slow_queries';

-- Lock contention analysis
SELECT * FROM performance_schema.data_locks\G
SELECT * FROM performance_schema.data_lock_waits\G
SELECT * FROM sys.innodb_lock_waits\G

-- Full InnoDB status walkthrough
SHOW ENGINE INNODB STATUS\G

-- Connection health
SHOW STATUS LIKE 'Threads%';
SHOW STATUS LIKE 'Connections';
SHOW STATUS LIKE 'Aborted%';
SHOW STATUS LIKE 'Max_used_connections';
SHOW VARIABLES LIKE 'max_connections';
SELECT * FROM sys.host_summary;
```

```bash
# Slow query log analysis
docker exec mysql-lab mysqldumpslow -s t /var/lib/mysql/slow.log

# Quick server health check
docker exec mysql-lab mysqladmin -u root -prootpass status
docker exec mysql-lab mysqladmin -u root -prootpass extended-status | \
  grep -i 'threads\|connections\|slow'
```

**Read**:
- [Performance Schema](https://dev.mysql.com/doc/refman/8.4/en/performance-schema.html)
- [sys Schema](https://dev.mysql.com/doc/refman/8.4/en/sys-schema.html)
- [MySQL Memory Allocation](https://dev.mysql.com/doc/refman/8.4/en/memory-use.html)
- [InnoDB I/O Configuration](https://dev.mysql.com/doc/refman/8.4/en/innodb-performance-configuration.html)
- [Slow Query Log](https://dev.mysql.com/doc/refman/8.4/en/slow-query-log.html)
- [SHOW ENGINE INNODB STATUS](https://dev.mysql.com/doc/refman/8.4/en/innodb-standard-monitor.html)
- *High Performance MySQL* Ch.3 — Server Performance Profiling
- *High Performance MySQL* Ch.4 — Configuring Memory and I/O
- Percona Toolkit: `pt-query-digest`, `pt-stalk`

**Deliverable**: Create a MySQL health check runbook — a step-by-step checklist for diagnosing production performance issues:

1. **Connections**: Are we hitting `max_connections`? High `Aborted_connects`? What does `SHOW PROCESSLIST` reveal?
2. **Slow queries**: What does `sys.statement_analysis` show? Which digests dominate latency? Any full table scans?
3. **Locks**: Are there lock waits in `sys.innodb_lock_waits`? Long-running transactions in `INNODB_TRX`?
4. **I/O**: What are the hottest files in `sys.io_global_by_file_by_bytes`? Is `innodb_io_capacity` appropriate for the storage?
5. **Buffer pool**: What's the hit ratio? How many dirty pages? Is the buffer pool sized correctly?
6. **Replication**: Is `Seconds_Behind_Source` growing? Are parallel workers keeping up?

For each step, include the exact SQL commands and what "healthy" vs "unhealthy" looks like.

---

## How It All Fits Together

```
Data changes on the source server
  → Binary Log (5.1): change captured as binlog events (two-phase commit with redo log)
  → Replication (5.2): binlog events flow to replicas
      → Async: fast, risk data loss
      → Semi-sync: source waits for ACK, safer
      → Group Replication: Paxos consensus, automatic failover
  → Backup (5.3): mysqldump / XtraBackup captures a point-in-time snapshot
      → PITR: restore backup + replay binlog to target time
      → CLONE: provision new replicas instantly
  → Observability (5.4): Performance Schema + sys schema + slow log + INNODB STATUS
      → Diagnose: connections → queries → locks → I/O → buffer pool → replication
      → Tune: memory (buffer pool 70-80% RAM), I/O (io_capacity for storage type), queries (indexes, rewrites)
```

**The full picture across all phases**:
- **Phase 1** gave you the map of how a query flows through mysqld
- **Phase 2** showed you how InnoDB stores, caches, and protects data (buffer pool, B+ Tree, MVCC, redo log)
- **Phase 3** taught you how transactions and locks enforce correctness under concurrency
- **Phase 4** showed you how the optimizer and indexes make queries fast
- **Phase 5** takes it all beyond a single server: sharing changes, surviving failures, and seeing what's happening

---

## Progress Tracker

| # | Topic | Status |
|---|-------|--------|
| 5.1 | Binary Log & Change Propagation | [ ] |
| 5.2 | Replication & High Availability | [ ] |
| 5.3 | Backup & Recovery | [ ] |
| 5.4 | Observability & Troubleshooting | [ ] |
