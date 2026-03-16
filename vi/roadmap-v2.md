# Lộ trình MySQL Internals v2

Một roadmap theo first principles, bám sát thực tế backend production và góc nhìn kiến trúc.

## Trình tự

```text
0. Ranh giới hệ thống
1. Lưu trữ
2. Đồng thời
3. Độ bền dữ liệu
4. Optimizer
5. Tối ưu hiệu năng
6. Replication / HA / Vận hành
```

## Vì sao đi theo thứ tự này

```text
Hệ thống này thực chất là gì?
  -> Dữ liệu được lưu như thế nào?
    -> Nhiều người dùng dùng chung dữ liệu ra sao mà vẫn đúng?
      -> Khi crash thì dữ liệu sống sót bằng cách nào?
        -> Hệ thống chọn execution plan như thế nào?
          -> Ta chẩn đoán và tune ra sao?
            -> Ta vận hành nó an toàn ở quy mô lớn thế nào?
```

## Bản đồ phase

### Phase 0 — Ranh giới hệ thống
- process `mysqld`
- SQL layer vs storage engine
- handler API
- client protocol
- luồng thực thi query
- thread model

### Phase 1 — Lưu trữ
- page
- buffer pool
- B+ tree
- clustered index vs secondary index
- bookmark lookup
- page split/merge

### Phase 2 — Đồng thời
- transaction
- isolation levels
- MVCC
- undo log
- read view
- record/gap/next-key lock
- deadlock
- tác động của long transaction

### Phase 3 — Độ bền dữ liệu
- WAL
- redo log
- log buffer
- LSN
- checkpoint
- doublewrite
- crash recovery

### Phase 4 — Optimizer
- statistics và cardinality
- cost model
- join order
- chọn access path
- EXPLAIN / EXPLAIN ANALYZE
- optimizer trace

### Phase 5 — Tối ưu hiệu năng
- chẩn đoán slow query
- phân rã độ trễ
- CPU vs I/O vs lock wait
- anti-pattern
- tuning theo workload
- tuning SQL và index an toàn

### Phase 6 — Replication / HA / Vận hành
- binary log
- GTID
- các mode replication
- ngữ nghĩa failover
- backup / PITR
- observability
- health check production

## Definition of done
Một phase chỉ xem là xong khi đủ cả bốn điều:
1. giải thích lại được cơ chế từ first principles
2. tái hiện hoặc quan sát được trong lab
3. nối được với symptom thật ở production
4. dùng được để ra quyết định kiến trúc / tuning

## Cách dùng gợi ý
- Đọc file này trước.
- Sau đó vào README của phase hiện tại.
- Dùng `production-symptom-map.md` và `cheatsheet.md` như tài liệu tham chiếu lặp lại.
