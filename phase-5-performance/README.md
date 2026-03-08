# Phase 5: Performance & Production

Use MySQL's built-in instrumentation to diagnose bottlenecks and tune for production workloads.

> Each topic below is **self-contained**. Jump into any item freely — prerequisites are noted where needed.

## Topic Map

```
┌─────────────────────────────────────────────────────┐
│        5.1 Performance Schema & sys Schema           │
│    (instruments, consumers, wait/statement analysis) │
├──────────────────────┬──────────────────────────────┤
│ 5.2 Memory           │ 5.3 I/O Optimization         │
│ Architecture         │ (tablespace, page size,       │
│ (global/session      │  compression, io_capacity)    │
│  buffers, tuning)    │                               │
├──────────────────────┴──────────────────────────────┤
│              5.4 Troubleshooting                     │
│    (slow query, lock contention, replication lag,    │
│     INNODB STATUS breakdown)                         │
└─────────────────────────────────────────────────────┘
```

---

## 5.1 Performance Schema & sys Schema

**Goal**: Master MySQL's built-in observability framework for diagnosing production issues.

**Key Concepts**:
- **Performance Schema**: in-memory instrumentation engine, zero disk I/O overhead. Collects events about server execution
- **Instruments**: named probes in the source code — `wait/io/file/innodb/innodb_data_file`, `statement/sql/select`, etc.
- **Consumers**: tables that store collected events — `events_statements_history`, `events_waits_current`, etc.
- **Event hierarchy**: transactions → statements → stages → waits
- **Digests**: normalized SQL pattern — groups similar queries by structure (ignoring literal values)
- **sys schema**: user-friendly views built on top of performance_schema — human-readable sizes, latencies, summaries
- **Key sys views**: `statement_analysis`, `host_summary`, `innodb_buffer_stats_by_table`, `schema_unused_indexes`, `io_global_by_file_by_bytes`

**Lab**:
```sql
-- Performance Schema status
SHOW VARIABLES LIKE 'performance_schema';

-- List enabled instruments
SELECT NAME, ENABLED, TIMED FROM performance_schema.setup_instruments
  WHERE ENABLED = 'YES' LIMIT 20;

-- List consumers
SELECT * FROM performance_schema.setup_consumers;

-- Top 10 queries by total latency
SELECT * FROM sys.statement_analysis LIMIT 10;

-- Queries doing full table scans
SELECT * FROM sys.statements_with_full_table_scans LIMIT 10;

-- Top waits (what is MySQL spending time on?)
SELECT event_name, COUNT_STAR, SUM_TIMER_WAIT/1e12 AS total_wait_sec
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC LIMIT 15;

-- Statement digests: grouped query patterns
SELECT DIGEST_TEXT, COUNT_STAR, AVG_TIMER_WAIT/1e12 AS avg_sec,
       SUM_ROWS_EXAMINED, SUM_ROWS_SENT
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC LIMIT 10;

-- Unused indexes (candidates for removal)
SELECT * FROM sys.schema_unused_indexes WHERE object_schema = 'lab';

-- Table I/O waits
SELECT * FROM sys.schema_table_statistics WHERE table_schema = 'lab';
```

**Read**:
- [Performance Schema](https://dev.mysql.com/doc/refman/8.4/en/performance-schema.html)
- [sys Schema](https://dev.mysql.com/doc/refman/8.4/en/sys-schema.html)
- *High Performance MySQL* Ch.3 — Performance Schema

**Deliverable**: Run a workload (multiple queries), then use `sys.statement_analysis` and `events_waits_summary` to identify the top 3 bottlenecks. Propose fixes for each.

---

## 5.2 Memory Architecture

**Goal**: Understand MySQL's memory allocation model and tune buffers for production.

**Prerequisites**: Phase 2.1 (Buffer Pool) — the largest memory consumer.

**Key Concepts**:
- **Global buffers** (shared across all connections):
  - `innodb_buffer_pool_size`: 70-80% of available RAM on dedicated servers
  - `innodb_log_buffer_size`: redo log write buffer (default 16MB)
  - `table_open_cache`: cached table descriptors
  - `table_definition_cache`: cached .frm metadata
- **Session buffers** (per-connection, allocated on demand):
  - `sort_buffer_size`: ORDER BY, GROUP BY operations
  - `join_buffer_size`: joins without index (NLJ, Hash Join buffer)
  - `read_buffer_size`: sequential scan buffer
  - `read_rnd_buffer_size`: MRR buffer for random reads
  - `tmp_table_size` / `max_heap_table_size`: in-memory temp tables before spilling to disk
- **Memory formula**: `global_buffers + (max_connections × session_buffers)` = total potential usage
- **Memory instrumentation**: `performance_schema.memory_summary_global_by_event_name` tracks every allocation
- **Tuning principle**: measure actual usage first with performance_schema, then tune. Never blindly increase

**Lab**:
```sql
-- Global buffer settings
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'innodb_log_buffer_size';
SHOW VARIABLES LIKE 'table_open_cache';

-- Session buffer settings
SHOW VARIABLES LIKE 'sort_buffer_size';
SHOW VARIABLES LIKE 'join_buffer_size';
SHOW VARIABLES LIKE 'read_buffer_size';
SHOW VARIABLES LIKE 'tmp_table_size';

-- Actual memory usage (sys schema)
SELECT * FROM sys.memory_global_total;
SELECT * FROM sys.memory_global_by_current_bytes LIMIT 15;

-- Memory by user/host
SELECT * FROM sys.memory_by_host_by_current_bytes;
SELECT * FROM sys.memory_by_user_by_current_bytes;

-- Temp table usage: disk vs memory
SHOW STATUS LIKE 'Created_tmp%';
SELECT
  Created_tmp_disk_tables / (Created_tmp_tables + 0.001) * 100 AS pct_disk_tmp
FROM (
  SELECT
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status
     WHERE VARIABLE_NAME = 'Created_tmp_disk_tables') AS Created_tmp_disk_tables,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status
     WHERE VARIABLE_NAME = 'Created_tmp_tables') AS Created_tmp_tables
) t;

-- Max connections impact
SHOW VARIABLES LIKE 'max_connections';
SHOW STATUS LIKE 'Max_used_connections';
```

**Read**:
- [MySQL Memory Allocation](https://dev.mysql.com/doc/refman/8.4/en/memory-use.html)
- [InnoDB Buffer Pool Configuration](https://dev.mysql.com/doc/refman/8.4/en/innodb-buffer-pool.html)
- *High Performance MySQL* Ch.4 — Configuring Memory

**Deliverable**: Calculate the theoretical max memory usage for the current configuration. Compare with actual usage from `sys.memory_global_total`. Propose a tuning plan.

---

## 5.3 I/O Optimization

**Goal**: Understand InnoDB's I/O subsystem and optimize for storage performance.

**Prerequisites**: Phase 2.1 (Buffer Pool), Phase 2.5 (Redo Log).

**Key Concepts**:
- **Tablespace types**:
  - **System tablespace** (`ibdata1`): shared, contains undo logs (before 8.0), change buffer, doublewrite
  - **File-per-table** (`innodb_file_per_table=ON`): each table has own `.ibd` file. Easier management, `OPTIMIZE TABLE` reclaims space
  - **General tablespace**: user-created shared tablespace for grouping tables
  - **Undo tablespace** (8.0+): dedicated files for undo logs, supports auto-truncation
- **Page size**: default 16KB. Smaller pages (4K/8K) → better for OLTP with small rows, larger pages (32K/64K) → better for OLAP/bulk reads
- **Compression**:
  - `ROW_FORMAT=COMPRESSED`: compress pages + store in buffer pool compressed. CPU vs I/O trade-off
  - **Transparent page compression** (`COMPRESSION='zlib'`): OS-level hole punching, requires sparse file support
- **I/O capacity**: `innodb_io_capacity` (normal flushing rate, default 200), `innodb_io_capacity_max` (burst rate, default 2000)
  - SSD: set to 1000–10000+. HDD: keep at 200
- **I/O scheduling**: `innodb_flush_method = O_DIRECT` — bypass OS cache, avoid double buffering (recommended for dedicated servers)
- **Read-ahead**: `innodb_read_ahead_threshold` — prefetch sequential pages, reduces random I/O for scans

**Lab**:
```sql
-- Tablespace configuration
SHOW VARIABLES LIKE 'innodb_file_per_table';
SHOW VARIABLES LIKE 'innodb_data_file_path';

-- Tablespace info
SELECT * FROM information_schema.INNODB_TABLESPACES
  WHERE NAME LIKE 'lab/%';

-- I/O capacity settings
SHOW VARIABLES LIKE 'innodb_io_capacity%';
SHOW VARIABLES LIKE 'innodb_flush_method';
SHOW VARIABLES LIKE 'innodb_read_ahead_threshold';

-- I/O activity (sys schema)
SELECT * FROM sys.io_global_by_file_by_bytes LIMIT 15;
SELECT * FROM sys.io_global_by_wait_by_bytes LIMIT 10;

-- InnoDB I/O metrics
SELECT NAME, COUNT, AVG_COUNT FROM information_schema.INNODB_METRICS
  WHERE SUBSYSTEM = 'os' AND STATUS = 'enabled';

-- Page size
SHOW VARIABLES LIKE 'innodb_page_size';

-- Data and index size per table
SELECT TABLE_NAME,
  ROUND(DATA_LENGTH / 1024 / 1024, 2) AS data_mb,
  ROUND(INDEX_LENGTH / 1024 / 1024, 2) AS index_mb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'lab';
```

```bash
# I/O stats from OS level
docker exec mysql-lab ls -lh /var/lib/mysql/lab/
docker exec mysql-lab ls -lh /var/lib/mysql/ibdata1
docker exec mysql-lab ls -lh /var/lib/mysql/undo_*
```

**Read**:
- [InnoDB Tablespaces](https://dev.mysql.com/doc/refman/8.4/en/innodb-tablespace.html)
- [InnoDB Page Compression](https://dev.mysql.com/doc/refman/8.4/en/innodb-page-compression.html)
- [InnoDB I/O Configuration](https://dev.mysql.com/doc/refman/8.4/en/innodb-performance-configuration.html)
- *High Performance MySQL* Ch.4 — Configuring I/O

**Deliverable**: Profile I/O activity using `sys.io_global_by_file_by_bytes`. Identify the hottest files. Propose `innodb_io_capacity` settings for SSD vs HDD.

---

## 5.4 Troubleshooting

**Goal**: Develop a systematic approach to diagnosing common MySQL production issues.

**Prerequisites**: All previous phases provide context for troubleshooting.

**Key Concepts**:
- **Slow query log**: captures queries exceeding `long_query_time`. Analyze with `mysqldumpslow` or `pt-query-digest`
- **Lock contention diagnosis**:
  - `performance_schema.data_locks`: current locks held
  - `performance_schema.data_lock_waits`: who is waiting for whom
  - `sys.innodb_lock_waits`: human-readable lock wait summary
  - `SHOW ENGINE INNODB STATUS` → TRANSACTIONS section
- **Replication lag diagnosis**:
  - `SHOW REPLICA STATUS` → `Seconds_Behind_Source`
  - `performance_schema.replication_applier_status_by_worker`: per-worker lag
  - Root causes: single-threaded apply, heavy DDL, network, replica hardware
- **Connection issues**: `max_connections` hit, `Aborted_connects`, `wait_timeout`
- **SHOW ENGINE INNODB STATUS sections**:
  - SEMAPHORES: mutex/rw-lock contention
  - TRANSACTIONS: active/locked transactions, undo log usage
  - FILE I/O: pending I/O operations
  - BUFFER POOL AND MEMORY: hit ratio, dirty pages, free pages
  - LOG: redo log LSN, checkpoint lag
  - ROW OPERATIONS: reads, inserts, updates, deletes per second
- **Systematic approach**: check → connections → slow queries → locks → I/O → buffer pool → replication

**Lab**:
```sql
-- Slow query log
SHOW VARIABLES LIKE 'slow_query_log%';
SHOW VARIABLES LIKE 'long_query_time';
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 0.5;

-- Generate a slow query (full table scan)
SELECT * FROM lab.employees WHERE name LIKE '%test%';

-- Check slow log
SHOW GLOBAL STATUS LIKE 'Slow_queries';

-- Lock contention analysis
SELECT * FROM sys.innodb_lock_waits\G

-- Full InnoDB status — parse each section
SHOW ENGINE INNODB STATUS\G

-- Connection analysis
SHOW STATUS LIKE 'Threads%';
SHOW STATUS LIKE 'Connections';
SHOW STATUS LIKE 'Aborted%';
SHOW STATUS LIKE 'Max_used_connections';
SELECT * FROM sys.host_summary;

-- Table scan ratio
SHOW STATUS LIKE 'Handler_read%';

-- Process list with details
SELECT * FROM performance_schema.processlist
  WHERE COMMAND != 'Sleep'
  ORDER BY TIME DESC;
```

```bash
# Slow query log analysis
docker exec mysql-lab mysqldumpslow -s t /var/lib/mysql/slow.log

# Quick health check
docker exec mysql-lab mysqladmin -u root -prootpass status
docker exec mysql-lab mysqladmin -u root -prootpass extended-status | grep -i 'threads\|connections\|slow'
```

**Read**:
- [Slow Query Log](https://dev.mysql.com/doc/refman/8.4/en/slow-query-log.html)
- [SHOW ENGINE INNODB STATUS](https://dev.mysql.com/doc/refman/8.4/en/innodb-standard-monitor.html)
- *High Performance MySQL* Ch.3 — Server Performance Profiling
- Percona Toolkit: `pt-query-digest`, `pt-stalk`

**Deliverable**: Create a MySQL health check runbook: a step-by-step checklist to diagnose slow performance, covering connections → queries → locks → I/O → buffer pool → replication.

---

## Progress Tracker

| # | Topic | Status |
|---|-------|--------|
| 5.1 | Performance Schema & sys Schema | [ ] |
| 5.2 | Memory Architecture | [ ] |
| 5.3 | I/O Optimization | [ ] |
| 5.4 | Troubleshooting | [ ] |
