# Phase 2: InnoDB Deep Dive — 5 phút

## Mục tiêu
Hiểu cấu trúc dữ liệu, cơ chế transaction và đảm bảo crash recovery của InnoDB. Các topic self-contained.

---

## 2.1 Buffer Pool
- InnoDB đọc/ghi theo **trang 16KB** (không theo dòng). Buffer pool = cache lớn cho data + index pages.
- **Ba danh sách**: free list (trang trống), LRU list (trang đã cache), flush list (dirty pages).
- **LRU**: young sublist (nóng), old sublist (lạnh). Trang mới vào **midpoint** (đầu old), được đưa lên young sau lần truy cập thứ hai trong `innodb_old_blocks_time`.
- **Adaptive flushing**: thread nền flush dirty page theo tốc độ sinh redo. Nhiều buffer pool instance giảm mutex contention.

**Lab nhanh**: `SHOW VARIABLES LIKE 'innodb_buffer_pool%'`; `INNODB_BUFFER_POOL_STATS`; công thức hit ratio từ `Innodb_buffer_pool_reads` / `Innodb_buffer_pool_read_requests`; `sys.innodb_buffer_stats_by_table`.

---

## 2.2 B+ Tree Index
- **Clustered index**: mỗi bảng có đúng một; leaf = full row, xếp theo PK. Không có PK → dùng UNIQUE NOT NULL đầu tiên hoặc row ID ẩn.
- **Secondary index**: leaf chứa giá trị PK (bookmark); truy vấn: secondary → PK → clustered (double lookup).
- **Page split/merge**: leaf đầy → tách; trang dưới 50% → merge. Index merge: optimizer có thể kết hợp nhiều single-column index.

**Lab nhanh**: `SHOW INDEX`; `EXPLAIN FORMAT=TREE` cho query dùng PK vs secondary vs covering index; `mysql.innodb_index_stats` (size).

---

## 2.3 Transaction & MVCC
- **ACID**: atomicity (undo), consistency, isolation (MVCC + lock), durability (redo).
- **Isolation**: READ UNCOMMITTED, READ COMMITTED (RC), REPEATABLE READ (RR, mặc định), SERIALIZABLE.
- **Undo log**: lưu phiên bản cũ để rollback và đọc MVCC. **Read view**: snapshot transaction active (RR: lần đọc đầu; RC: mỗi câu lệnh). Hàng visible nếu `trx_id` thỏa quy tắc (min_active, current).
- **Purge**: dọn undo không còn read view nào dùng. Transaction chạy lâu → undo phình → chậm.

**Lab nhanh**: So sánh RR vs RC: 2 session, một SELECT trong transaction, một UPDATE+COMMIT; session 1 SELECT lại — RR thấy giá trị cũ, RC thấy mới. `INNODB_TRX`, `Innodb_purge%`.

---

## 2.4 Locking
- **Record lock**: khóa một dòng index. **Gap lock**: khóa khe giữa hai dòng (chống phantom ở RR). **Next-key** = record + gap phía trước (mặc định RR).
- **Intention lock** (IS, IX): mức bảng. **Insert intention**: gap lock đặc biệt cho insert song song vào cùng gap.
- **Deadlock**: InnoDB dựng wait-for graph, phát hiện cycle → rollback transaction “nhỏ hơn” (theo rollback cost). RC chỉ dùng record lock (không gap).

**Lab nhanh**: `performance_schema.data_locks`, `data_lock_waits`; thử gap lock (SELECT ... FOR UPDATE; insert vào gap bị block); tạo deadlock 2 session rồi xem `SHOW ENGINE INNODB STATUS` → LATEST DETECTED DEADLOCK.

---

## 2.5 Redo Log & WAL
- **WAL**: thay đổi ghi vào redo **trước** khi flush dirty page lên data file.
- **Redo log**: vòng tròn, kích thước cố định; ghi thay đổi vật lý trang. **LSN**: vị trí redo tăng đơn điệu. **Checkpoint**: LSN mà mọi dirty page đã flush; vùng redo trước checkpoint có thể tái dùng.
- **Doublewrite**: ghi trang qua vùng doublewrite trước rồi mới tới vị trí thật → chống torn page khi crash.
- **Crash recovery**: redo (áp dụng đã commit) → undo (rollback chưa commit). `innodb_flush_log_at_trx_commit`: 1 = flush mỗi commit (an toàn nhất).

**Lab nhanh**: `SHOW VARIABLES LIKE 'innodb_redo_log_capacity|innodb_flush_log_at_trx_commit'`; `SHOW ENGINE INNODB STATUS` → LOG (LSN, checkpoint); `Innodb_dblwr%`; xem file trong `#innodb_redo/`.

---

## Luồng tổng hợp
Client ghi → Buffer Pool (trang dirty) → Redo (WAL) → B+ Tree → MVCC (undo) + Locking → Checkpoint flush → Crash: redo replay + undo rollback.
