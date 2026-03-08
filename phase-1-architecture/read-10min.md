# Phase 1: Architecture Foundation — 10 phút

## Mục tiêu
Hiểu MySQL xử lý query end-to-end: từ kết nối client đến I/O storage engine. Các topic self-contained.

---

## 1.1 Server Architecture (mysqld)
- **mysqld**: một process, đa luồng; thành phần chính:
  - **Connection Manager**: xác thực, gán thread, quản lý connection.
  - **SQL Layer**: parser, preprocessor, optimizer, executor — không phụ thuộc engine.
  - **Storage Engine Layer**: truy cập dữ liệu qua Handler API (InnoDB, MyISAM, MEMORY...).
  - **Replication Layer**: ghi binlog, replication IO/SQL threads.
- **Bộ nhớ**: buffer pool (InnoDB data/index pages), table cache (file descriptor bảng), thread cache, table definition cache. Query cache đã bỏ ở 8.0 (global mutex).
- **Data dictionary** (8.0+): system tables InnoDB thay .frm; **basedir**, **datadir**.

**Lab**: `SELECT @@version; SHOW VARIABLES LIKE 'innodb_buffer_pool_size|table_open_cache|thread_cache_size';` — data dictionary: `information_schema.TABLES` schema `mysql`; `SHOW STATUS LIKE 'Uptime|Questions|Com_select';` — shell: `docker exec mysql-lab ps aux | grep mysqld`, `ls -la /var/lib/mysql/lab/`.

---

## 1.2 Client Protocol & Connection Lifecycle
- **Transport**: TCP 3306, Unix socket, shared memory (Windows).
- **Handshake**: (1) TCP established → (2) server greeting (protocol version, connection ID, auth plugin) → (3) client gửi user, auth, schema → (4) OK/ERR.
- **Command**: COM_QUERY (SQL), COM_STMT_PREPARE/EXECUTE (prepared, hiệu quả hơn), COM_PING, COM_QUIT. Result set: số cột → định nghĩa cột → từng dòng.
- **Trạng thái**: connecting → authenticated → sleep → query/locked/sending data → sleep → COM_QUIT. `max_connections`, `wait_timeout`; Aborted_connects/Aborted_clients khi auth lỗi hoặc client đứt không COM_QUIT.

**Lab**: `SHOW PROCESSLIST`, `SHOW STATUS LIKE 'Connections|Aborted%'`, `SHOW VARIABLES LIKE 'max_connections|wait_timeout'`; `performance_schema.session_connect_attrs`, `accounts`.

---

## 1.3 Thread Model
- **Thread-per-connection** (mặc định): mỗi client 1 OS thread; scale kém khi > ~5000 (context switch, ~1MB/thread). **Thread cache**: disconnect → thread vào cache, connection mới tái sử dụng; đánh giá qua `Threads_created` vs `Connections`.
- **Thread pool** (Enterprise/Percona): pool worker cố định, hàng đợi ưu tiên (query mới vs query trong transaction).
- **Background (InnoDB)**: master thread (flush, purge, change buffer), page cleaner, purge, IO read/write, log writer; contention xem SEMAPHORES trong `SHOW ENGINE INNODB STATUS`.

**Lab**: `SHOW VARIABLES LIKE 'thread_handling|thread_cache_size'`; `SHOW STATUS LIKE 'Threads%'`; `performance_schema.threads` (BACKGROUND/FOREGROUND); `SHOW VARIABLES LIKE 'innodb_*_io_threads|innodb_purge_threads|innodb_page_cleaners'`.

---

## 1.4 Query Execution Flow
- **Parser**: SQL → AST; lỗi cú pháp 1064.
- **Preprocessor**: kiểm tra bảng/cột tồn tại, quyền, mở rộng `*`, alias.
- **Optimizer**: cost-based; access path (full scan, index, range), join order, join algorithm (NLJ, Hash Join, BKA), subquery (materialization, semi-join); output execution plan (iterator tree 8.0+).
- **Executor**: Init() → Read() trên từng iterator; gọi Handler API; engine đọc/ghi trang.
- **Flow**: Client SQL → Parser (AST) → Preprocessor → Optimizer (plan) → Executor (iterator + handler) → Engine → Result set → client.

**Lab**: `EXPLAIN`, `EXPLAIN FORMAT=TREE`, `EXPLAIN FORMAT=JSON`, `EXPLAIN ANALYZE`; `SET optimizer_trace='enabled=on'` + query + `information_schema.OPTIMIZER_TRACE`; general_log để xem query vào.

---

## 1.5 Storage Engine Layer
- **Handler API**: ha_open, ha_rnd_init/ha_rnd_next (full scan), ha_index_init/ha_index_read/ha_index_next, ha_write_row, ha_update_row, ha_delete_row, ha_external_lock. **Handlerton**: create/open/close/commit/rollback.
- **Khả năng**: transaction (InnoDB), foreign key (InnoDB), full-text, spatial; engine: InnoDB (mặc định), MyISAM, MEMORY, CSV, Archive, Blackhole, NDB. Mỗi bảng có thể ENGINE khác nhau.
- **Lab**: `SHOW ENGINES`; `information_schema.TABLES` (ENGINE, ROW_FORMAT); `SHOW TABLE STATUS`; `FLUSH STATUS` + query + `SHOW STATUS LIKE 'Handler%'`; tạo bảng MEMORY/Blackhole để so sánh.

---

## 1.6 InnoDB vs MyISAM
- **So sánh**: InnoDB — ACID, row lock, redo/undo, crash recovery, FK, MVCC, clustered index, .ibd, buffer pool. MyISAM — không transaction, table lock, REPAIR sau crash, không FK, không MVCC, heap + index riêng, .MYD/.MYI, key buffer; COUNT(*) lưu sẵn.
- InnoDB thắng nhờ crash safety + row lock + MVCC cho OLTP. MyISAM còn dùng read-only/analytics rất hiếm; 8.0 system tables toàn InnoDB.

**Lab**: `SHOW ENGINES`; `SHOW ENGINE INNODB STATUS`; `information_schema.TABLES` (ENGINE, size); `INNODB_METRICS`; so sánh file .ibd vs .MYD/.MYI trên disk.

---

## Tổng hợp luồng
Client connect (TCP 3306) → Connection Manager (handshake, auth, gán thread) → Thread (1/connection) → COM_QUERY → Parser (AST) → Preprocessor → Optimizer (plan) → Executor (iterator, Handler API) → Storage Engine (buffer pool/disk) → Result → thread sleep hoặc cache khi disconnect.
