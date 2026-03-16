# Bản đồ symptom production

Nối MySQL internals với việc chẩn đoán sự cố production.

| Symptom | Nguyên nhân nội tại có khả năng cao | Nên kiểm tra gì | Hành động khả dĩ |
|---|---|---|---|
| Query đột nhiên chậm | plan xấu, statistics cũ, thiếu index, lock wait | `EXPLAIN ANALYZE`, `OPTIMIZER_TRACE`, `sys.statement_analysis`, lock waits | analyze table, thêm/sửa index, viết lại SQL, giảm contention |
| Throughput tụt khi có nhiều concurrent requests | lock contention, deadlock, hot rows, long transaction | `SHOW ENGINE INNODB STATUS`, `performance_schema.data_locks`, transaction views | giảm phạm vi transaction, đổi access pattern, tune retry |
| Read latency cao | miss buffer pool, random I/O, access path kém | buffer pool stats, file I/O views, plan analysis | tune index, tăng buffer pool, giảm scan |
| Commit latency tăng vọt | áp lực flush redo, fsync đắt, checkpoint pressure | redo/checkpoint metrics, log status | tune log settings cẩn thận, cải thiện storage, giảm burst |
| Replica lag tăng dần | apply chậm, transaction lớn, nghẽn I/O, thiếu song song | replication status, applier worker stats, pattern transaction từ source | bật/tune parallel apply, giảm transaction lớn, cải thiện I/O |
| Memory pressure | global buffers quá lớn, quá nhiều connections, session buffers lớn | memory views, `max_connections`, cấu hình buffer | right-size buffers, giới hạn concurrency, tune app pool |
| App gặp deadlock/timeout | xung đột ghi, range locks, thứ tự transaction không nhất quán | InnoDB status, lock waits, review pattern SQL | thống nhất thứ tự ghi, rút ngắn transaction, cải thiện index |
| Recovery lâu sau crash | checkpoint age lớn, undo/redo phải xử lý nhiều, long transaction | redo/checkpoint age, recovery logs, footprint transaction | giảm checkpoint lag, tránh transaction quá dài |

## Mẫu sử dụng
Với mọi vấn đề hiệu năng hoặc nhất quán dữ liệu, thử map theo chuỗi:

```text
symptom
  -> cơ chế có khả năng gây ra
  -> tín hiệu cụ thể cần kiểm tra
  -> cách giảm thiểu an toàn nhất trước
```
