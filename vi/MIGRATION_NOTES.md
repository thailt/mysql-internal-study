# Ghi chú Migration — Roadmap v2

Repo này đã được refactor từ cấu trúc phase ban đầu sang một trục học v2 rõ ràng hơn.

## Vì sao có v2
Cấu trúc cũ có nhiều material tốt, nhưng một số mối quan tâm đang bị trộn vào nhau theo cách không tối ưu cho thực tế backend/production:
- concurrency chưa được nhấn mạnh đủ như một phase cấp cao
- optimizer internals và performance tuning đứng quá sát nhau
- storage và durability bị ghép chung trong một phase

## Trình tự chuẩn mới

```text
0. Ranh giới hệ thống
1. Lưu trữ
2. Đồng thời
3. Độ bền dữ liệu
4. Optimizer
5. Tối ưu hiệu năng
6. Replication / HA / Vận hành
```

## Ánh xạ lịch sử (legacy -> v2)

| Material lịch sử | Đích v2 |
|---|---|
| phase-1 architecture | `phase-0-system-boundaries/*` |
| phase-2 storage/durability (phần storage) | `phase-1-storage/*` |
| phase-2 storage/durability (phần durability) | `phase-3-durability/*` |
| Các chủ đề MVCC/locking trước đây nằm rải trong material cũ | `phase-2-concurrency/*` |
| phase-3 query optimization | `phase-4-optimizer/*` |
| phase-4 query performance | `phase-5-performance-tuning/*` |
| phase-5 scale/production | `phase-6-replication-ha-ops/*` |

## Trạng thái migration
- Các folder phase v2 từ 0–6 đã tồn tại
- Mỗi phase v2 đều có:
  - `README.md`
  - `read-1min.md`
  - `read-5min.md`
  - `read-10min.md`
  - `read-full.md`
- Các folder phase legacy đã được retire và xóa khỏi working tree

## Đường đọc chuẩn hiện tại
1. `README.md`
2. `roadmap-v2.md`
3. `first-principles-learning.md`
4. folder phase v2 hiện tại
5. `production-symptom-map.md`
6. `cheatsheet.md`

## Ghi chú
Ánh xạ lịch sử vẫn được giữ trong file này để việc chuyển đổi số phase còn dễ hiểu, dù các folder cũ không còn hiện diện nữa.
