# MySQL theo First Principles

Học từ **chân lý nền** (vật lý, ràng buộc, bài toán gốc), rồi suy ra từng cơ chế. Không bắt đầu bằng “MySQL có buffer pool”, mà bắt đầu bằng “vì sao một database engine buộc phải cần thứ như buffer pool?”.

---

## Cách dùng file này

Đây là **canonical first-principles map** của repo.

Thứ tự dùng nên là:
1. `README.md`
2. `roadmap-v2.md`
3. file này
4. phase README hiện tại
5. reading ladder của phase đó (`read-1min` -> `read-full`)

---

## Bước 0: Đặt câu hỏi đúng

- Sai: "InnoDB buffer pool là gì?"
- Đúng: "Một database engine cần giải quyết những bài toán gốc nào, rồi InnoDB chọn giải pháp gì?"

---

## Nguyên lý 0: Hệ thống và ranh giới

**Sự thật:**
- Một process (`mysqld`) phải xử lý connection, SQL, execution coordination, và tương tác với storage engine.
- SQL là tầng logic; engine là nơi dữ liệu thật sự được truy cập/lưu trữ.
- Không có bản đồ layer thì mọi internals phía sau đều dễ bị lẫn.

**Suy ra:**
1. Phải tách được **SQL layer** và **storage engine layer**.
2. Phải hiểu **handler API** là boundary giữa hai tầng.
3. Phải nắm luồng query end-to-end: client -> parser -> optimizer -> executor -> handler -> engine.

**Ánh xạ v2:**
- `phase-0-system-boundaries/`

---

## Nguyên lý 1: Lưu trữ — Disk chậm, RAM nhanh

**Sự thật:**
- Disk chậm hơn RAM rất nhiều.
- Đọc/ghi theo row trực tiếp trên disk là không thực tế.
- Cache trong RAM là bắt buộc nếu muốn hiệu năng tốt.

**Suy ra:**
1. Phải có **đơn vị I/O** là page/block.
2. Phải có **page cache trong RAM** -> buffer pool.
3. Phải có **cấu trúc tổ chức dữ liệu** để tìm page nhanh -> B+ tree.
4. Phải phân biệt clustered index và secondary index.

**Ánh xạ v2:**
- `phase-1-storage/`

---

## Nguyên lý 2: Đồng thời — Nhiều actor, một dữ liệu chia sẻ

**Sự thật:**
- Nhiều transaction cùng đọc/ghi một kho dữ liệu.
- Nếu khóa mọi thứ để an toàn thì throughput sụp.
- Nếu không khóa/không versioning thì kết quả trở nên khó chấp nhận.

**Suy ra:**
1. Phải có **transaction boundary**.
2. Phải có **visibility rules** -> isolation.
3. Readers nhiều khi cần snapshot thay vì block writers -> MVCC.
4. Cần **undo log** và **read view** cho snapshot reads.
5. Writers/ranges vẫn cần lock -> record/gap/next-key locks.
6. Cyclic wait là tự nhiên -> deadlock detection.

**Ánh xạ v2:**
- `phase-2-concurrency/`

---

## Nguyên lý 3: Bền vững — Commit rồi thì phải sống sót qua crash

**Sự thật:**
- RAM mất khi crash/power loss.
- Ghi trực tiếp page ra data file mỗi commit là quá đắt.
- Page write có thể bị torn khi crash giữa chừng.

**Suy ra:**
1. Phải **ghi log trước** -> WAL.
2. Phải có **redo log** để recover committed changes.
3. Phải có **LSN** và **checkpoint** để quản lý tiến độ durability.
4. Phải có **doublewrite** để bảo vệ page integrity.
5. Recovery sẽ là **redo committed work + undo incomplete work**.

**Ánh xạ v2:**
- `phase-3-durability/`

---

## Nguyên lý 4: Chọn kế hoạch thực thi — Cùng một SQL có nhiều cách chạy

**Sự thật:**
- Một query có thể có nhiều execution plans.
- Chênh lệch cost giữa các plan có thể rất lớn.
- Plan tốt phụ thuộc vào statistics/cardinality, join order, access path.

**Suy ra:**
1. Cần **cost-based optimizer**.
2. Cần statistics/cardinality để đánh giá candidate plans.
3. Join order là quyết định hạng nhất.
4. Phải đọc được `EXPLAIN`, `EXPLAIN ANALYZE`, và khi cần thì `optimizer trace`.

**Ánh xạ v2:**
- `phase-4-optimizer/`

---

## Nguyên lý 5: Tuning — “Slow” là symptom, không phải diagnosis

**Sự thật:**
- Chậm có thể do plan, lock, I/O, CPU, memory, temp work, workload shape.
- Thay đổi bừa rất dễ sửa sai chỗ hoặc tạo side effects mới.

**Suy ra:**
1. Phải bắt đầu bằng **bottleneck classification**.
2. Phải nối symptom -> mechanism -> evidence -> smallest safe change.
3. Phải phân biệt plan issue với contention issue.
4. Phải đo **before/after**, không tune bằng cảm giác.

**Ánh xạ v2:**
- `phase-5-performance-tuning/`
- `production-symptom-map.md`

---

## Nguyên lý 6: Mở rộng / HA / Operations — Một server không đủ

**Sự thật:**
- Một node có giới hạn capacity, availability, recovery, observability.
- Replication, HA, backup/PITR, runbooks đều là một phần của production reality.

**Suy ra:**
1. Phải phân biệt **redo log** và **binlog**.
2. Phải hiểu **async vs semi-sync** là trade-off latency/safety.
3. Phải hiểu **replication is not backup**.
4. Phải có **backup + PITR**.
5. Phải có **observability + operational runbook**.

**Ánh xạ v2:**
- `phase-6-replication-ha-ops/`

---

## Thứ tự học đề xuất (v2)

| Bước | Nguyên lý | Câu hỏi first-principles | Phase v2 |
|---|---|---|---|
| 0 | Hệ thống & ranh giới | Query đi qua những layer nào? SQL layer và engine khác nhau ở đâu? | `phase-0-system-boundaries` |
| 1 | Lưu trữ | Vì sao cần page, buffer pool, B+ tree? | `phase-1-storage` |
| 2 | Đồng thời | Làm sao readers/writers cùng tồn tại mà vẫn đúng? | `phase-2-concurrency` |
| 3 | Bền vững | Commit thực sự nghĩa là gì khi crash? | `phase-3-durability` |
| 4 | Chọn plan | Vì sao optimizer chọn plan này? | `phase-4-optimizer` |
| 5 | Tuning | Slow là do plan, lock, I/O hay gì khác? | `phase-5-performance-tuning` |
| 6 | Scale / HA / Ops | Làm sao chạy MySQL an toàn ngoài single-node world? | `phase-6-replication-ha-ops` |

---

## Progress tracker (v2)

| # | Nguyên lý | Phase | Status |
|---|---|---|---|
| 0 | Hệ thống & ranh giới | `phase-0-system-boundaries` | [ ] |
| 1 | Lưu trữ | `phase-1-storage` | [ ] |
| 2 | Đồng thời | `phase-2-concurrency` | [ ] |
| 3 | Bền vững | `phase-3-durability` | [ ] |
| 4 | Chọn plan | `phase-4-optimizer` | [ ] |
| 5 | Tuning | `phase-5-performance-tuning` | [ ] |
| 6 | Mở rộng / HA / Ops | `phase-6-replication-ha-ops` | [ ] |

---

## Tóm lại

Nếu phải nhớ một chuỗi duy nhất, hãy nhớ:

```text
System
-> Storage
-> Concurrency
-> Durability
-> Optimizer
-> Performance Tuning
-> Replication / HA / Operations
```

Đây là xương sống của roadmap v2.
