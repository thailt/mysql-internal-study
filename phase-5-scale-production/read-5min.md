# Phase 5: Performance & Production — 5 phút

## Mục tiêu
Dùng instrumentation có sẵn để chẩn đoán nghẽn và tune production. Các topic self-contained.

---

## 5.1 Performance Schema & sys Schema
- **Performance Schema**: instrumentation in-memory, không ghi đĩa; thu thập event thực thi (wait, statement, stage, transaction). **Instruments**: probe trong code (wait/io/file/innodb/..., statement/sql/select). **Consumers**: bảng lưu event (events_statements_history, events_waits_current...).
- **Event hierarchy**: transaction → statement → stage → wait. **Digest**: SQL chuẩn hóa (nhóm query cùng cấu trúc, bỏ literal). **sys schema**: view dễ đọc trên performance_schema — statement_analysis, host_summary, innodb_buffer_stats_by_table, schema_unused_indexes, io_global_by_file_by_bytes.

**Lab nhanh**: performance_schema=ON; setup_instruments, setup_consumers; sys.statement_analysis (top latency); statements_with_full_table_scans; events_waits_summary_global_by_event_name (top waits); events_statements_summary_by_digest; schema_unused_indexes; schema_table_statistics.

---

## 5.2 Memory Architecture
- **Global**: innodb_buffer_pool_size (70–80% RAM dedicated server), innodb_log_buffer_size, table_open_cache, table_definition_cache. **Session** (per connection): sort_buffer_size, join_buffer_size, read_buffer_size, read_rnd_buffer_size, tmp_table_size/max_heap_table_size.
- **Công thức**: global_buffers + (max_connections × session_buffers) = tổng tiềm năng. **performance_schema.memory_summary_global_by_event_name** theo dõi cấp phát. Nguyên tắc: đo trước (sys.memory_*), rồi mới tune; không tăng mù.

**Lab nhanh**: SHOW VARIABLES (innodb_buffer_pool_size, table_open_cache, sort_buffer_size, join_buffer_size, tmp_table_size); sys.memory_global_total, memory_global_by_current_bytes; memory_by_host_by_current_bytes; Created_tmp_disk_tables vs Created_tmp_tables; max_connections, Max_used_connections.

---

## 5.3 I/O Optimization
- **Tablespace**: system (ibdata1), file-per-table (.ibd), general, undo (8.0+). **Page size**: mặc định 16KB; nhỏ (4K/8K) cho OLTP dòng nhỏ, lớn (32K/64K) cho scan. **Compression**: ROW_FORMAT=COMPRESSED; transparent page compression (zlib, hole punching).
- **innodb_io_capacity** (tốc độ flush bình thường), **innodb_io_capacity_max** (burst); SSD: 1000–10000+, HDD: 200. **innodb_flush_method=O_DIRECT** tránh double buffering. **Read-ahead**: innodb_read_ahead_threshold.

**Lab nhanh**: innodb_file_per_table, innodb_data_file_path; INNODB_TABLESPACES; innodb_io_capacity*, innodb_flush_method, innodb_read_ahead_threshold; sys.io_global_by_file_by_bytes, io_global_by_wait_by_bytes; INNODB_METRICS (os); innodb_page_size; DATA_LENGTH, INDEX_LENGTH per table.

---

## 5.4 Troubleshooting
- **Slow query log**: long_query_time; phân tích mysqldumpslow, pt-query-digest. **Lock**: data_locks, data_lock_waits, sys.innodb_lock_waits; SHOW ENGINE INNODB STATUS → TRANSACTIONS.
- **Replication lag**: SHOW REPLICA STATUS → Seconds_Behind_Source; replication_applier_status_by_worker; nguyên nhân: single-threaded apply, DDL, mạng, replica yếu.
- **INNODB STATUS**: SEMAPHORES (contention), TRANSACTIONS (active, undo), FILE I/O, BUFFER POOL AND MEMORY, LOG (LSN, checkpoint), ROW OPERATIONS. **Runbook**: connections → slow queries → locks → I/O → buffer pool → replication.

**Lab nhanh**: slow_query_log, long_query_time; sys.innodb_lock_waits; SHOW ENGINE INNODB STATUS; Threads*, Connections, Aborted*, Max_used_connections; sys.host_summary; Handler_read*; processlist (non-Sleep).

---

## Tóm tắt
Performance Schema + sys (statement/waits/digest, unused index) → Memory (global + session, đo rồi tune) → I/O (tablespace, io_capacity, O_DIRECT) → Troubleshooting (slow log, locks, lag, INNODB STATUS, runbook).
