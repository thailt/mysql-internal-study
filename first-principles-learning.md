# MySQL theo First Principles

Học từ **chân lý nền** (vật lý, ràng buộc, bài toán gốc), rồi suy ra từng thành phần. Không bắt đầu bằng "MySQL có buffer pool", mà bằng "tại sao mọi engine kiểu InnoDB đều cần thứ giống buffer pool".

---

## Bước 0: Đặt câu hỏi đúng

- Sai: "InnoDB buffer pool là gì?"
- Đúng: "Để đọc/ghi dữ liệu bền vững, hệ thống phải giải quyết những vấn đề gốc nào? Rồi InnoDB chọn giải pháp gì?"

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

**Ánh xạ InnoDB:** Buffer pool = cache; page 16KB = đơn vị I/O; LRU (young/old) = eviction; flush list + adaptive flushing = đẩy dirty ra disk. Đọc doc Buffer Pool **sau khi** đã tự trả lời: "nếu mình viết engine, mình sẽ cache thế nào?".

---

## Nguyên lý 2: Tìm dữ liệu — Scan O(n) không chấp nhận được

**Sự thật:**
- Full scan = O(n) row (hoặc O(n) page).
- Cần **point lookup** (theo key) và **range scan** (theo khoảng) với cost gần O(log n).

**Suy ra:**
1. Cần **cấu trúc có thứ tự** trên key.
2. Cấu trúc đó phải **cân bằng** để không bị thoái hóa (linked list).
3. Range scan hiệu quả → **leaf level phải liên kết** (không phải leo lên root mỗi lần) → B+ tree, không chỉ B-tree.
4. Có **một cách sắp xếp "chính"** chứa full row (clustered); các cách truy cập khác chỉ cần key + con trỏ tới bản gốc (secondary index → PK).

**Ánh xạ InnoDB:** B+ tree; clustered index = PK (hoặc row id ẩn); secondary index = (secondary key → PK); bookmark lookup = secondary → clustered. Đọc B+ Tree / Index Types **sau khi** đã vẽ trên giấy: "một bảng có (id, name, dept) — clustered và một secondary index trên dept trông thế nào?".

---

## Nguyên lý 3: Đồng thời — Nhiều client, một kho dữ liệu

**Sự thật:**
- Nhiều transaction cùng lúc đọc/ghi.
- Nếu khóa toàn bảng → throughput thấp.
- Cần **isolation**: kết quả phải có thể giải thích được (serializable hoặc snapshot).

**Suy ra:**
1. **Readers không chặn writers, writers không chặn readers** trừ khi cần đảm bảo nhất quán → cần **phiên bản dữ liệu** (multi-version).
2. Phiên bản cũ không xóa ngay → cần **undo log** (hoặc tương đương) để vừa rollback vừa phục vụ đọc snapshot.
3. **Snapshot** = tại thời điểm T, "tôi thấy tập transaction nào đã commit?" → **read view**.
4. Writer phải **khóa** để hai writer không sửa cùng row/gap → record lock, gap lock (nếu cần tránh phantom).
5. Khóa nhiều thứ theo thứ tự khác nhau → **deadlock**; cần phát hiện và phá (rollback một bên).

**Ánh xạ InnoDB:** MVCC + undo log; read view (RR vs RC); record/gap/next-key lock; deadlock detection. Đọc Transaction Model & Locking **sau khi** đã tự thiết kế: "làm sao để SELECT không block UPDATE và ngược lại?".

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

**Ánh xạ InnoDB:** Redo log, LSN, checkpoint; WAL; doublewrite buffer; crash recovery = redo (replay) + undo (rollback chưa commit). Đọc Redo Log & Doublewrite **sau khi** đã trả lời: "sau khi kill -9, khi mysqld start lại, nó làm từng bước gì?".

---

## Thứ tự học đề xuất (first principles → implementation)

| Bước | Câu hỏi first principle | Sau đó mới đọc |
|------|--------------------------|----------------|
| 1 | Cache disk trong RAM thế nào? Đơn vị I/O? Eviction? Dirty flush? | Buffer Pool (2.1) |
| 2 | Tìm theo key/range O(log n), range scan không leo root? Một "bảng" có mấy cây? | B+ Tree, Index Types (2.2) |
| 3 | Đọc snapshot không block ghi; ghi cần khóa gì? Phantom? Deadlock? | Transaction, MVCC, Locking (2.3, 2.4) |
| 4 | Commit = gì trên disk? Crash xong khởi động lại làm gì? Torn page? | Redo, WAL, Doublewrite (2.5) |

---

## Cách áp dụng

- Với **mỗi topic** trong phase-2-innodb: viết ra 1–2 câu hỏi "tại sao phải có thứ này?" / "bài toán gốc là gì?".
- Tự trả lời bằng **nguyên lý** (disk/RAM, O(log n), isolation, durability) trước khi mở MySQL docs.
- Sau đó đọc docs để xem **InnoDB chọn implementation cụ thể thế nào** (16KB page, midpoint insertion, next-key lock, v.v.).
- Lab: dùng để **kiểm chứng** nguyên lý (ví dụ: thấy RR không thấy phantom nhờ gap lock; thấy LSN tăng khi commit).

---

## Tóm lại

**First principles:** Storage (disk vs RAM, page, cache) → Access (B+ tree, clustered/secondary) → Concurrency (MVCC, read view, locks) → Durability (WAL, redo, checkpoint, doublewrite).

**Không:** "Học buffer pool rồi học B+ tree rồi học lock" theo checklist.  
**Có:** "Tại sao cần cache? → Cần eviction thế nào? → InnoDB làm bằng buffer pool và LRU thế này."

Bạn đã có sẵn phase-2-innodb với README + lab; dùng tài liệu này làm **khung hỏi đáp** trước khi đọc từng mục trong README.
