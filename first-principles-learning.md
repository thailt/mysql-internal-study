# MySQL theo First Principles

Học từ **chân lý nền** (vật lý, ràng buộc, bài toán gốc), rồi suy ra từng thành phần. Không bắt đầu bằng "MySQL có buffer pool", mà bằng "tại sao mọi engine kiểu InnoDB đều cần thứ giống buffer pool".

---

## Bước 0: Đặt câu hỏi đúng

- Sai: "InnoDB buffer pool là gì?"
- Đúng: "Để đọc/ghi dữ liệu bền vững, hệ thống phải giải quyết những vấn đề gốc nào? Rồi InnoDB chọn giải pháp gì?"

---

## Nguyên lý 0: Hệ thống và ranh giới — Trước khi tối ưu, phải biết máy chạy thế nào

**Sự thật:**
- Một process (`mysqld`) phải xử lý SQL, quản lý kết nối, và đọc/ghi dữ liệu.
- SQL là ngôn ngữ trừu tượng; disk/engine là nơi dữ liệu thật sự nằm.
- Nhiều engine (InnoDB, MyISAM, …) với trade-off khác nhau.

**Suy ra:**
1. Phải **tách lớp**: lớp SQL (parser, optimizer, executor) độc lập với lớp lưu trữ (engine).
2. **Handler API** = hợp đồng giữa server và engine; server không biết chi tiết engine.
3. **Luồng query**: Client → Connection → Parser → Optimizer → Executor → Handler API → Engine → Disk/RAM.
4. Không nắm được bản đồ này thì mọi câu hỏi "tại sao InnoDB làm X?" sẽ thiếu ngữ cảnh.

**Ánh xạ:** Phase 1 — Server Architecture (1.1), Client Protocol (1.2), Thread Model (1.3), Query Execution Flow (1.4), Storage Engine Layer (1.5), InnoDB vs MyISAM (1.6). Đọc Phase 1 **trước** khi đi sâu bất kỳ phase nào.

---

## Nguyên lý 1: Lưu trữ — Disk chậm, RAM nhanh

**Sự thật:**
- Disk: latency ms, throughput có giới hạn.
- RAM: latency ns, throughput cao hơn nhiều.
- Ứng dụng cần đọc/ghi **theo đơn vị nhỏ** (row), nhưng disk hiệu quả khi I/O **theo khối lớn** (block).

**Suy ra:**
1. Phải có **đơn vị I/O** (page/block) — không đọc từng row từ disk.
2. Phải có **cache trong RAM** để giảm đọc disk.
3. Cache hữu hạn → cần **chính sách thay thế** (LRU hoặc biến thể).
4. Dữ liệu sửa trong RAM chưa kịp ghi xuống disk → **dirty page** và **flush**.

**Ánh xạ:** Phase 2.1 — Page I/O & Buffer Pool. Buffer pool = cache; page 16KB = đơn vị I/O; LRU (young/old) = eviction; flush list + adaptive flushing. Tự trả lời trước: "nếu mình viết engine, mình sẽ cache thế nào?".

---

## Nguyên lý 2: Tìm dữ liệu — Scan O(n) không chấp nhận được

**Sự thật:**
- Full scan = O(n) row (hoặc O(n) page).
- Cần **point lookup** (theo key) và **range scan** (theo khoảng) với cost gần O(log n).

**Suy ra:**
1. Cần **cấu trúc có thứ tự** trên key.
2. Cấu trúc đó phải **cân bằng** để không bị thoái hóa (linked list).
3. Range scan hiệu quả → **leaf level phải liên kết** (không phải leo lên root mỗi lần) → B+ tree.
4. Có **một cách sắp xếp "chính"** chứa full row (clustered); các cách truy cập khác chỉ cần key + con trỏ tới bản gốc (secondary index → PK).

**Ánh xạ:** Phase 2.2 — B+ Tree & Data Organization. Clustered index = PK; secondary index = (key → PK); bookmark lookup. Vẽ trên giấy: bảng (id, name, dept) — clustered và secondary index trên dept trông thế nào?

---

## Nguyên lý 3: Đồng thời — Nhiều client, một kho dữ liệu

**Sự thật:**
- Nhiều transaction cùng lúc đọc/ghi.
- Nếu khóa toàn bảng → throughput thấp.
- Cần **isolation**: kết quả phải có thể giải thích được (serializable hoặc snapshot).

**Suy ra:**
1. **Readers không chặn writers, writers không chặn readers** trừ khi cần đảm bảo nhất quán → cần **phiên bản dữ liệu** (multi-version).
2. Phiên bản cũ không xóa ngay → cần **undo log** để vừa rollback vừa phục vụ đọc snapshot.
3. **Snapshot** = tại thời điểm T, "tôi thấy tập transaction nào đã commit?" → **read view**.
4. Writer phải **khóa** để hai writer không sửa cùng row/gap → record lock, gap lock (tránh phantom).
5. Khóa nhiều thứ theo thứ tự khác nhau → **deadlock**; cần phát hiện và phá (rollback một bên).

**Ánh xạ:** Phase 2 (trong các tài liệu InnoDB) hoặc phase riêng Concurrency — MVCC, undo log, read view (RR vs RC), record/gap/next-key lock, deadlock detection. Tự thiết kế trước: "làm sao để SELECT không block UPDATE và ngược lại?".

---

## Nguyên lý 4: Bền vững — Commit rồi thì không mất khi crash

**Sự thật:**
- RAM mất khi tắt máy; disk (và fsync) tồn tại.
- Ghi trực tiếp page từ RAM xuống đúng vị trí file rất dễ bị **torn write** (crash giữa chừng → nửa page cũ, nửa mới).

**Suy ra:**
1. **Commit = cam kết** rằng sau khi server chết, khi khởi động lại vẫn thấy thay đổi đã commit.
2. Cách an toàn: **ghi log thay đổi trước** (write-ahead), rồi mới coi là "đã commit". Khi crash, **replay log** để tái tạo.
3. Log tuần tự, append-only → **redo log**. Vị trí trong log = **LSN**.
4. Chỉ khi dirty page đã flush hết tới một LSN thì đoạn log trước đó mới có thể tái sử dụng → **checkpoint**.
5. Torn page: ghi page qua **vùng trung gian** (doublewrite) rồi mới ghi vào đích; recovery dùng bản lành từ doublewrite.

**Ánh xạ:** Phase 2.3 (WAL & Redo Log), Phase 2.4 (Checkpoint, Doublewrite & Crash Recovery). Tự trả lời: "sau khi kill -9, khi mysqld start lại, nó làm từng bước gì?".

---

## Nguyên lý 5: Chọn kế hoạch thực thi — Nhiều cách chạy một query, chọn thế nào?

**Sự thật:**
- Một query có thể có **nhiều plan** (full scan vs index, join order A vs B, NLJ vs Hash Join).
- Chọn sai plan → chênh lệch thời gian hàng bậc (ms vs giây).
- Con người không thể liệt kê hết; cần **mô hình cost** và **tìm kiếm không gian plan**.

**Suy ra:**
1. **Cost-based optimizer**: ước lượng cost (I/O, CPU, memory) cho từng candidate plan, chọn cost thấp nhất.
2. Cost model = bảng hằng số (server_cost, engine_cost) + thống kê (số row, selectivity).
3. Cần **đọc plan** (EXPLAIN, EXPLAIN ANALYZE) để kiểm chứng và debug.
4. Index đúng = giảm cost; SQL không sargable = optimizer không tận dụng được index.

**Ánh xạ:** Phase 3 (Query Optimization), Phase 4 (Query Performance) — 3.1/4.1 Optimizer, 3.2/4.2 Execution Plan, 3.3/4.3 Index Strategy, 3.4/4.4 Query Rewrite. Tự hỏi trước: "với JOIN 3 bảng, có bao nhiêu thứ tự join? Optimizer loại trừ thế nào?".

---

## Nguyên lý 6: Mở rộng và sẵn sàng — Một server có giới hạn

**Sự thật:**
- Một instance có giới hạn throughput, single point of failure, và giới hạn quan sát.
- Cần **chia sẻ thay đổi** cho server khác (replication), **sống sót khi chết** (HA), **phục hồi sai lỗi** (backup/PITR), **thấy rõ đang xảy ra gì** (observability).

**Suy ra:**
1. **Binary log** = stream thay đổi có thứ tự; replica áp dụng để đồng bộ. Redo + binlog phải nhất quán → **two-phase commit (XA)**.
2. **Replication**: async (nhanh, rủi ro mất dữ liệu), semi-sync (an toàn hơn, latency cao hơn), Group Replication (consensus, failover tự động).
3. **Backup + PITR**: logical (mysqldump) hoặc physical (XtraBackup, CLONE); replay binlog tới thời điểm cần.
4. **Observability**: Performance Schema, sys schema — không tối ưu được thứ không đo được.

**Ánh xạ:** Phase 5 — 5.1 Binary Log, 5.2 Replication & HA, 5.3 Backup & Recovery, 5.4 Observability & Troubleshooting. Tự hỏi: "server chết lúc 12:00:05, replica lag 2s — failover xong mất tối đa bao nhiêu commit?".

---

## Thứ tự học đề xuất (first principles → implementation)

| Bước | Nguyên lý | Câu hỏi first principle | Đọc (phase.topic) |
|------|-----------|--------------------------|-------------------|
| 0 | Hệ thống & ranh giới | Luồng query đi qua đâu? Tại sao tách SQL và engine? | Phase 1 (1.1–1.6) |
| 1 | Lưu trữ | Cache disk trong RAM thế nào? Đơn vị I/O? Eviction? Dirty flush? | Phase 2.1 |
| 2 | Tìm dữ liệu | Tìm theo key/range O(log n)? Một bảng có mấy cây? Bookmark lookup? | Phase 2.2 |
| 3 | Đồng thời | Đọc snapshot không block ghi; ghi cần khóa gì? Phantom? Deadlock? | (Phase 2 / tài liệu MVCC & Locking) |
| 4 | Bền vững | Commit = gì trên disk? Crash xong khởi động lại làm gì? Torn page? | Phase 2.3, 2.4 |
| 5 | Chọn plan | Nhiều plan cho một query — optimizer chọn thế nào? Cost? EXPLAIN? | Phase 3, Phase 4 |
| 6 | Mở rộng & HA | Chia sẻ thay đổi? Failover? Backup/PITR? Đo đạc? | Phase 5 |

---

## Cách áp dụng

- Với **mỗi topic** trong mỗi phase: viết ra 1–2 câu hỏi "tại sao phải có thứ này?" / "bài toán gốc là gì?".
- Tự trả lời bằng **nguyên lý** (disk/RAM, O(log n), isolation, durability, cost, scale) trước khi mở MySQL docs hoặc README phase.
- Sau đó đọc docs/README để xem **MySQL/InnoDB chọn implementation cụ thể thế nào**.
- Lab: dùng để **kiểm chứng** nguyên lý (ví dụ: thấy LSN tăng khi commit; thấy gap lock chặn phantom trong RR).

---

## Progress tracker (First Principles)

| # | Nguyên lý | Phase | Status |
|---|-----------|-------|--------|
| 0 | Hệ thống & ranh giới | 1 | [ ] |
| 1 | Lưu trữ (page, buffer pool) | 2.1 | [ ] |
| 2 | Tìm dữ liệu (B+ tree) | 2.2 | [ ] |
| 3 | Đồng thời (MVCC, locking) | 2 / tài liệu | [ ] |
| 4 | Bền vững (WAL, redo, doublewrite) | 2.3, 2.4 | [ ] |
| 5 | Chọn plan (optimizer, index) | 3, 4 | [ ] |
| 6 | Mở rộng & HA (binlog, replication, backup, observability) | 5 | [ ] |

---

## Tóm lại

**First principles (theo thứ tự):**  
0. Hệ thống & ranh giới (Phase 1) → 1. Lưu trữ (2.1) → 2. Tìm dữ liệu (2.2) → 3. Đồng thời (MVCC, lock) → 4. Bền vững (2.3, 2.4) → 5. Chọn plan (Phase 3, 4) → 6. Mở rộng & HA (Phase 5).

**Không:** Học theo checklist "buffer pool → B+ tree → lock" mà không hỏi tại sao.  
**Có:** "Tại sao cần cache? → Eviction thế nào? → InnoDB làm bằng buffer pool và LRU thế này." Dùng file này làm **khung hỏi đáp** trước khi đọc từng phase.
