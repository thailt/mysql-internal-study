# Phase 2: InnoDB Deep Dive — 10 phút

## Mục tiêu
Hiểu cấu trúc dữ liệu nội bộ, transaction và đảm bảo crash recovery của InnoDB. Các topic self-contained.

---

## 2.1 Buffer Pool
- InnoDB I/O theo **trang 16KB**. Buffer pool cache data + index pages; ba list: **free** (trang trống), **LRU** (đã cache), **flush** (dirty).
- **LRU**: young (nóng) / old (lạnh). Trang mới vào **midpoint** (đầu old); lên young sau lần đọc thứ hai trong `innodb_old_blocks_time` (tránh full scan đẩy hết hot).
- **Adaptive flushing**: flush dirty theo tốc độ sinh redo. **Buffer pool instances**: giảm mutex contention.

**Lab**: `SHOW VARIABLES LIKE 'innodb_buffer_pool_size|innodb_buffer_pool_instances|innodb_old_blocks_pct|innodb_old_blocks_time'`; `information_schema.INNODB_BUFFER_POOL_STATS`; hit ratio = `(1 - Innodb_buffer_pool_reads/Innodb_buffer_pool_read_requests)*100` từ global_status; `SHOW STATUS LIKE 'Innodb_buffer_pool_pages%'`; `sys.innodb_buffer_stats_by_table` cho schema lab.

---

## 2.2 B+ Tree Index
- **Clustered index**: một/bảng; leaf = full row, theo PK. Không PK → UNIQUE NOT NULL đầu tiên → hoặc row ID ẩn 6 byte.
- **Secondary index**: leaf = giá trị PK (bookmark). **Bookmark lookup**: secondary → lấy PK → clustered → lấy row. **Covering index**: đủ cột trong index → không cần lookup (Extra: Using index).
- **Page split**: leaf đầy → tách; **merge**: dưới MERGE_THRESHOLD (50%). **Index merge**: optimizer kết hợp nhiều single-column index (intersection/union).

**Lab**: `SHOW INDEX FROM lab.employees|orders`; EXPLAIN FORMAT=TREE cho PK lookup, secondary lookup, covering; `information_schema.INNODB_METRICS` (index_page); `mysql.innodb_index_stats` (size). So sánh file .ibd trên disk.

---

## 2.3 Transaction & MVCC
- **ACID**: atomicity (undo), consistency, isolation (MVCC + locks), durability (redo). **Isolation**: READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ (default), SERIALIZABLE.
- **Undo log**: lưu phiên bản cũ; dùng cho rollback và đọc snapshot. **Read view**: snapshot transaction ID active — RR: lần đọc đầu; RC: mỗi statement. Visibility: `trx_id < min_active` hoặc `trx_id = current`.
- **Purge thread**: xóa undo không còn read view dùng. Transaction dài → undo bloat → hiệu năng kém.

**Lab**: `SELECT @@transaction_isolation`; `INNODB_TRX`. Demo RR vs RC: session 1 START TRANSACTION + SELECT; session 2 UPDATE + COMMIT; session 1 SELECT lại (RR: cũ, RC: mới). `SHOW STATUS LIKE 'Innodb_purge%'`; INNODB_METRICS trx_undo/purge.

---

## 2.4 Locking
- **Record lock**: khóa một dòng. **Gap lock**: khóa khe giữa hai dòng (RR, chống phantom). **Next-key** = record + gap trước (mặc định RR). **Intention** (IS, IX): bảng. **Insert intention**: gap lock cho insert song song.
- **Deadlock**: wait-for graph; phát hiện cycle → rollback transaction “nhỏ hơn”. RC: chỉ record lock, không gap.

**Lab**: `performance_schema.data_locks`, `data_lock_waits`. Gap lock: session 1 SELECT ... FOR UPDATE (department = 'Engineering'); session 2 INSERT vào gap Engineering → bị block; xem data_lock_waits. Deadlock: 2 session UPDATE id 1 và 2 chéo nhau; `SHOW ENGINE INNODB STATUS` → LATEST DETECTED DEADLOCK.

---

## 2.5 Redo Log & WAL
- **WAL**: ghi redo trước khi flush dirty page. **Redo log**: vòng, kích thước cố định (8.0.30+ `innodb_redo_log_capacity`); ghi thay đổi vật lý trang.
- **LSN**: vị trí redo tăng đơn điệu. **Checkpoint**: LSN tới đó mọi dirty đã flush; redo trước checkpoint có thể reuse.
- **Doublewrite buffer**: ghi trang qua vùng doublewrite rồi mới tới vị trí thật → chống torn page (crash giữa chừng ghi).
- **Crash recovery**: redo (áp dụng đã commit) → undo (rollback chưa commit). `innodb_flush_log_at_trx_commit`: 1 = flush mỗi commit (an toàn nhất), 2 = OS cache, 0 = mỗi giây.

**Lab**: `SHOW VARIABLES LIKE 'innodb_redo_log_capacity|innodb_log_buffer_size|innodb_flush_log_at_trx_commit'`; `SHOW ENGINE INNODB STATUS` → LOG (Log sequence number, Last checkpoint); INNODB_METRICS (log); `SHOW STATUS LIKE 'Innodb_dblwr%'`; UPDATE rồi so sánh LSN trước/sau commit; list file `#innodb_redo/`.

---

## Tổng hợp
Client ghi → Buffer Pool (page dirty) → Redo (WAL) → B+ Tree → MVCC (undo) + Locking (row/gap) → Checkpoint flush → Crash: redo replay + undo rollback.
