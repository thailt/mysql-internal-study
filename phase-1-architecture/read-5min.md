# Phase 1: Architecture Foundation — 5 phút

## Mục tiêu
Hiểu MySQL xử lý query end-to-end: từ kết nối client đến I/O storage engine. Các topic tự chứa, có thể đọc theo thứ tự bất kỳ.

---

## 1.1 Server Architecture (mysqld)
- **mysqld** = một process, đa luồng; mọi thứ chạy trong process này.
- **Các thành phần**: Connection Manager (auth, gán thread), SQL Layer (parser, preprocessor, optimizer, executor — độc lập engine), Storage Engine Layer (pluggable qua Handler API), Replication Layer (binlog, IO/SQL thread).
- **Bộ nhớ dùng chung**: buffer pool (lớn nhất), table cache, thread cache, table definition cache. Query cache bỏ từ 8.0.
- **Data dictionary** (8.0+): system tables InnoDB thay .frm; **basedir** (binary), **datadir** (tablespace, log).

**Lab nhanh**: `SELECT @@version; SHOW VARIABLES LIKE 'innodb_buffer_pool_size'; SHOW STATUS LIKE 'Questions';` và `docker exec mysql-lab ps aux | grep mysqld`.

---

## 1.2 Client Protocol & Connection
- **Transport**: TCP 3306, Unix socket, hoặc shared memory (Windows).
- **Handshake**: server gửi greeting (version, connection ID, auth plugin) → client gửi user + auth → OK/ERR.
- **Command phase**: COM_QUERY (SQL text), COM_STMT_PREPARE/EXECUTE (prepared), COM_PING, COM_QUIT. Kết quả: số cột → định nghĩa cột → các dòng.
- **Trạng thái**: connecting → authenticated → sleep → query/sending data → COM_QUIT. Giới hạn: `max_connections`, `wait_timeout`.

**Lab nhanh**: `SHOW PROCESSLIST; SHOW STATUS LIKE 'Aborted%';`

---

## 1.3 Thread Model
- **Mặc định**: một OS thread cho mỗi connection; scale kém khi > ~5000 connection (context switch, ~1MB stack/thread).
- **Thread cache** (`thread_cache_size`): thread trả lại cache khi disconnect → giảm `pthread_create`. Kiểm tra: `Threads_created` << `Connections`.
- **Thread pool** (Enterprise): pool worker cố định, hàng đợi ưu tiên; phù hợp connection rất nhiều.
- **Background threads (InnoDB)**: page cleaner, purge, IO read/write, log writer; mutex contention xem trong `SHOW ENGINE INNODB STATUS` → SEMAPHORES.

---

## 1.4 Query Execution Flow
- **Parser**: SQL → AST; báo lỗi cú pháp.
- **Preprocessor**: kiểm tra bảng/cột, quyền, mở rộng `*`, alias.
- **Optimizer**: cost-based; chọn access path, join order, join algorithm (NLJ, Hash Join, BKA), chiến lược subquery; ra **execution plan** (iterator tree 8.0+).
- **Executor**: duyệt iterator tree, gọi Handler API; engine đọc/ghi trang.
- **Kết quả**: format hàng → gửi client.

**Lab nhanh**: `EXPLAIN FORMAT=TREE SELECT ...`; `EXPLAIN ANALYZE`; `SET optimizer_trace='enabled=on';` rồi xem `information_schema.OPTIMIZER_TRACE`.

---

## 1.5 Storage Engine Layer
- **Handler API** (`sql/handler.h`): server gọi ha_open, ha_rnd_init/ha_rnd_next (full scan), ha_index_* (index scan), ha_write_row, ha_update_row, ha_delete_row; **handlerton** đăng ký engine.
- **Khả năng theo engine**: transaction (InnoDB có, MyISAM không), foreign key, full-text, spatial. Mỗi bảng có thể `ENGINE=...` khác nhau.
- **Lab**: `SHOW ENGINES`; `SHOW TABLE STATUS`; `FLUSH STATUS` + query + `SHOW STATUS LIKE 'Handler%'`.

---

## 1.6 InnoDB vs MyISAM
- **InnoDB**: ACID, row lock, MVCC, redo/undo, crash recovery, clustered index (PK = data), .ibd. **MyISAM**: không transaction, table lock, .MYD + .MYI, COUNT(*) lưu sẵn.
- InnoDB thành mặc định từ 5.5 vì an toàn crash + đồng thời ghi tốt. MyISAM còn dùng trong vài trường hợp read-only/analytics rất hiếm; system tables 8.0 đều InnoDB.

---

## Luồng tổng hợp
Client connect → Connection Manager (handshake, auth) → Thread (1 thread/conn) → COM_QUERY → Parser → Preprocessor → Optimizer → Executor (Handler API) → Storage Engine (buffer pool/disk) → trả kết quả → thread sleep hoặc vào cache.
