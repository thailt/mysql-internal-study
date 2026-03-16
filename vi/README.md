# MySQL Internals Deep Dive — Tiếng Việt

Trang vào tiếng Việt cho phiên bản public của repo.

## Chuyển ngôn ngữ
- English: [../en/README.md](../en/README.md)
- Tiếng Việt: **bạn đang ở đây**

## Nên bắt đầu theo thứ tự này
1. [Lộ trình v2](roadmap-v2.md)
2. [MySQL theo First Principles](first-principles-learning.md)
3. README của phase đang học
4. [Bản đồ symptom production](production-symptom-map.md)
5. [Cheatsheet](cheatsheet.md)

## Repo này giúp gì
- dựng mental model rõ ràng giữa server layer và storage engine
- đi có thứ tự từ storage, MVCC, durability tới optimizer, tuning và vận hành
- nối internals với symptom production và quyết định kỹ thuật thực tế
- có lab Docker nhỏ gọn để tự kiểm chứng

## Điều hướng theo phase
- [Phase 0 — Ranh giới hệ thống](phase-0-system-boundaries/README.md)
- [Phase 1 — Lưu trữ](phase-1-storage/README.md)
- [Phase 2 — Đồng thời](phase-2-concurrency/README.md)
- [Phase 3 — Độ bền dữ liệu](phase-3-durability/README.md)
- [Phase 4 — Optimizer](phase-4-optimizer/README.md)
- [Phase 5 — Tối ưu hiệu năng](phase-5-performance-tuning/README.md)
- [Phase 6 — Replication / HA / Vận hành](phase-6-replication-ha-ops/README.md)

## Tài liệu hỗ trợ
- [Lộ trình v2](roadmap-v2.md)
- [Khung học first-principles](first-principles-learning.md)
- [Bản đồ symptom production](production-symptom-map.md)
- [Cheatsheet](cheatsheet.md)
- [Ghi chú migration](MIGRATION_NOTES.md)
- [Docker lab](docker/README.md)

## Ghi chú phạm vi
Lớp tiếng Việt hiện tập trung vào landing page, tài liệu cấp repo và README của từng phase.
Các file đọc sâu hơn (`read-1min`, `read-5min`, `read-10min`, `read-full`) hiện vẫn nằm ở thư mục phase gốc để tránh refactor lớn và giữ thay đổi an toàn.
