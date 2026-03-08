# Phase 2: InnoDB Deep Dive — 1 phút

**Mục tiêu**: Nắm cấu trúc dữ liệu nội bộ, transaction và crash recovery của InnoDB.

- **Buffer Pool (2.1)**: I/O theo trang 16KB; free list, LRU (young/old), flush list; adaptive flushing; nhiều instance giảm contention.
- **B+ Tree (2.2)**: Clustered index (leaf = full row), secondary index (leaf = PK); bookmark lookup; page split/merge.
- **Transaction & MVCC (2.3)**: Undo log lưu phiên bản cũ; read view (RR/RC); purge dọn undo; transaction dài → undo bloat.
- **Locking (2.4)**: Record lock, gap lock, next-key lock; RR dùng next-key, RC chỉ record; deadlock detection → rollback transaction nhỏ hơn.
- **Redo & WAL (2.5)**: Ghi redo trước khi flush dirty page; LSN, checkpoint; doublewrite chống torn page; crash recovery: redo → undo.

**Topic**: 2.1 Buffer Pool → 2.2 B+ Tree → 2.3 Transaction & MVCC → 2.4 Locking → 2.5 Redo Log & WAL.
