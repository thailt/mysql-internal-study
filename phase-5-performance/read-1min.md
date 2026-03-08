# Phase 5: Performance & Production — 1 phút

**Mục tiêu**: Dùng instrumentation có sẵn để chẩn đoán nghẽn và tune production.

- **Performance Schema & sys (5.1)**: Instruments, consumers; event hierarchy (transaction → statement → stage → wait); digest; sys (statement_analysis, schema_unused_indexes, io_global_by_file_by_bytes).
- **Memory (5.2)**: Global (buffer pool, log buffer, table caches); session (sort_buffer, join_buffer, read_buffer, tmp_table); công thức global + max_connections×session.
- **I/O (5.3)**: Tablespace (system, file-per-table, undo); page size; compression; innodb_io_capacity(/max); O_DIRECT; read-ahead.
- **Troubleshooting (5.4)**: Slow query log, data_locks/data_lock_waits, replication lag, SHOW ENGINE INNODB STATUS (SEMAPHORES, TRANSACTIONS, LOG, BUFFER POOL); runbook: connections → queries → locks → I/O → buffer pool → replication.

**Topic**: 5.1 Performance Schema & sys → 5.2 Memory → 5.3 I/O → 5.4 Troubleshooting.
