# Phase 5: Performance & Production — Full content

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

**Goal**: Master built-in observability for production diagnosis.

**Key Concepts**: Performance Schema (instruments, consumers, in-memory); event hierarchy (transactions → statements → stages → waits); digests; sys schema views (statement_analysis, host_summary, innodb_buffer_stats_by_table, schema_unused_indexes, io_global_by_file_by_bytes).

**Lab**: Full SQL from Phase 5 README (setup_instruments, setup_consumers, statement_analysis, statements_with_full_table_scans, events_waits_summary, events_statements_summary_by_digest, schema_unused_indexes, schema_table_statistics).

**Read**: Performance Schema, sys Schema, *High Performance MySQL* Ch.3.

**Deliverable**: Run workload; use statement_analysis and events_waits_summary to find top 3 bottlenecks; propose fixes.

---

## 5.2 Memory Architecture

**Goal**: Memory allocation model and buffer tuning.

**Key Concepts**: Global (buffer pool, log buffer, table caches); session (sort, join, read, tmp_table); formula global + max_connections×session; memory instrumentation; measure before tuning.

**Lab**: Variables (buffer pool, log buffer, table_open_cache, sort/join/read_buffer, tmp_table_size); sys.memory_global_total, memory_global_by_current_bytes; memory_by_host/user; Created_tmp_disk_tables vs Created_tmp_tables; max_connections, Max_used_connections.

**Read**: MySQL Memory Use, InnoDB Buffer Pool, *High Performance MySQL* Ch.4.

**Deliverable**: Compute theoretical max memory; compare with sys.memory_global_total; propose tuning plan.

---

## 5.3 I/O Optimization

**Goal**: InnoDB I/O subsystem and storage tuning.

**Key Concepts**: Tablespace types (system, file-per-table, general, undo); page size; compression; innodb_io_capacity(/max); O_DIRECT; read-ahead.

**Lab**: Tablespace config; INNODB_TABLESPACES; io_capacity, flush_method, read_ahead_threshold; sys.io_global_by_file_by_bytes, io_global_by_wait_by_bytes; INNODB_METRICS (os); DATA_LENGTH, INDEX_LENGTH.

**Read**: InnoDB Tablespaces, Page Compression, I/O Configuration, *High Performance MySQL* Ch.4.

**Deliverable**: Profile I/O with sys.io_global_by_file_by_bytes; identify hottest files; propose io_capacity for SSD vs HDD.

---

## 5.4 Troubleshooting

**Goal**: Systematic diagnosis of common production issues.

**Key Concepts**: Slow query log (mysqldumpslow, pt-query-digest); lock (data_locks, data_lock_waits, sys.innodb_lock_waits, INNODB STATUS TRANSACTIONS); replication lag (REPLICA STATUS, applier_status_by_worker); connections; INNODB STATUS sections (SEMAPHORES, TRANSACTIONS, FILE I/O, BUFFER POOL, LOG, ROW OPERATIONS); runbook order: connections → queries → locks → I/O → buffer pool → replication.

**Lab**: slow_query_log, long_query_time; slow query; innodb_lock_waits; SHOW ENGINE INNODB STATUS; Threads*, Connections, Aborted*; host_summary; Handler_read*; processlist. Bash: mysqldumpslow; mysqladmin status.

**Read**: Slow Query Log, SHOW ENGINE INNODB STATUS, *High Performance MySQL* Ch.3; Percona pt-query-digest, pt-stalk.

**Deliverable**: MySQL health check runbook — step-by-step for slow performance: connections → queries → locks → I/O → buffer pool → replication.

---

## Progress Tracker

| # | Topic | Status |
|---|-------|--------|
| 5.1 | Performance Schema & sys Schema | [ ] |
| 5.2 | Memory Architecture | [ ] |
| 5.3 | I/O Optimization | [ ] |
| 5.4 | Troubleshooting | [ ] |
