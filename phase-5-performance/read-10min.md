# Phase 5: Performance & Production — 10 phút

## Mục tiêu
Dùng instrumentation có sẵn để chẩn đoán nghẽn và tune production. Các topic self-contained.

---

## 5.1 Performance Schema & sys Schema
- **Performance Schema**: engine instrumentation in-memory, không I/O đĩa; thu thập event thực thi server. **Instruments**: probe có tên trong code (wait/io/file/innodb/innodb_data_file, statement/sql/select...). **Consumers**: bảng lưu event (events_statements_history, events_waits_current...). **Event hierarchy**: transactions → statements → stages → waits.
- **Digests**: SQL chuẩn hóa — nhóm query cùng cấu trúc (bỏ literal). **sys schema**: view dễ đọc trên performance_schema: statement_analysis (latency, rows), host_summary, innodb_buffer_stats_by_table, schema_unused_indexes, io_global_by_file_by_bytes.

**Lab**: performance_schema; setup_instruments (ENABLED=YES); setup_consumers; sys.statement_analysis (top 10); statements_with_full_table_scans; events_waits_summary_global_by_event_name (SUM_TIMER_WAIT, top 15); events_statements_summary_by_digest (DIGEST_TEXT, COUNT_STAR, AVG_TIMER_WAIT, rows); schema_unused_indexes (object_schema=lab); schema_table_statistics (lab).

---

## 5.2 Memory Architecture
- **Global buffers**: innodb_buffer_pool_size (70–80% RAM server chuyên dụng), innodb_log_buffer_size, table_open_cache, table_definition_cache. **Session buffers** (per connection): sort_buffer_size (ORDER BY, GROUP BY), join_buffer_size (join không index), read_buffer_size (sequential scan), read_rnd_buffer_size (MRR), tmp_table_size/max_heap_table_size (temp in-memory trước khi ra đĩa).
- **Công thức**: global_buffers + (max_connections × session_buffers) = tổng tiềm năng. **memory_summary_global_by_event_name** theo dõi cấp phát. Tune: đo thực tế (sys.memory_*) trước, không tăng mù.

**Lab**: SHOW VARIABLES (innodb_buffer_pool_size, innodb_log_buffer_size, table_open_cache; sort_buffer_size, join_buffer_size, read_buffer_size, tmp_table_size); sys.memory_global_total, memory_global_by_current_bytes (top 15); memory_by_host_by_current_bytes, memory_by_user_by_current_bytes; Created_tmp_disk_tables vs Created_tmp_tables (tỷ lệ disk temp); max_connections, Max_used_connections.

---

## 5.3 I/O Optimization
- **Tablespace**: system (ibdata1 — undo cũ, change buffer, doublewrite); file-per-table (.ibd — dễ quản lý, OPTIMIZE reclaim); general (user-defined); undo (8.0+). **Page size**: 16KB mặc định; nhỏ (4K/8K) cho OLTP dòng nhỏ; lớn (32K/64K) cho scan. **Compression**: ROW_FORMAT=COMPRESSED; transparent page compression (COMPRESSION='zlib', sparse file).
- **innodb_io_capacity** (flush bình thường, default 200), **innodb_io_capacity_max** (burst, 2000). SSD: 1000–10000+. **innodb_flush_method=O_DIRECT**: bỏ qua OS cache, tránh double buffering. **innodb_read_ahead_threshold**: prefetch sequential.

**Lab**: innodb_file_per_table, innodb_data_file_path; INNODB_TABLESPACES (lab/%); innodb_io_capacity*, innodb_flush_method, innodb_read_ahead_threshold; sys.io_global_by_file_by_bytes, io_global_by_wait_by_bytes; INNODB_METRICS (subsystem=os); innodb_page_size; information_schema.TABLES (DATA_LENGTH, INDEX_LENGTH, lab). Shell: ls lab/, ibdata1, undo_*.

---

## 5.4 Troubleshooting
- **Slow query log**: bật slow_query_log, long_query_time; phân tích bằng mysqldumpslow -s t hoặc pt-query-digest. **Lock contention**: performance_schema.data_locks (lock hiện có), data_lock_waits (ai chờ ai); sys.innodb_lock_waits; SHOW ENGINE INNODB STATUS → TRANSACTIONS.
- **Replication lag**: SHOW REPLICA STATUS → Seconds_Behind_Source; replication_applier_status_by_worker; nguyên nhân: single-threaded apply, DDL nặng, mạng, replica yếu. **Connection**: max_connections, Aborted_connects, wait_timeout. **INNODB STATUS**: SEMAPHORES (mutex/rw-lock), TRANSACTIONS (active, undo), FILE I/O, BUFFER POOL AND MEMORY (hit ratio, dirty, free), LOG (LSN, checkpoint), ROW OPERATIONS. **Runbook**: connections → slow queries → locks → I/O → buffer pool → replication.

**Lab**: slow_query_log, long_query_time; tạo query chậm (full scan) rồi xem Slow_queries; sys.innodb_lock_waits; SHOW ENGINE INNODB STATUS (giải thích từng section); Threads*, Connections, Aborted*, Max_used_connections; sys.host_summary; Handler_read*; processlist (COMMAND != Sleep, ORDER BY TIME). Bash: mysqldumpslow; mysqladmin status, extended-status.

---

## Tóm tắt
Performance Schema + sys (top queries, full scan, waits, digest, unused index) → Memory (global/session, đo rồi tune, tmp disk ratio) → I/O (tablespace, io_capacity, O_DIRECT, read-ahead) → Troubleshooting (slow log, locks, lag, INNODB STATUS, runbook).
