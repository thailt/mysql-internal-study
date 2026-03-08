# Phase 1: Architecture Foundation — 1 phút

**Mục tiêu**: Nắm luồng xử lý query từ client tới storage engine.

- **mysqld**: một process, đa luồng; gồm Connection Manager, SQL Layer (parser → optimizer → executor), Storage Engine (Handler API), Replication.
- **Bộ nhớ chính**: buffer pool (InnoDB), table cache, thread cache; query cache đã bỏ từ 8.0.
- **Client**: TCP 3306, handshake → auth → COM_QUERY/COM_STMT_* → result set → COM_QUIT.
- **Thread**: mặc định 1 thread/connection; thread cache tái sử dụng; thread pool (Enterprise) cho hàng nghìn connection.
- **Query flow**: Parser (SQL → AST) → Preprocessor (kiểm tra bảng/cột/quyền) → Optimizer (chọn plan) → Executor (iterator tree, gọi Handler API) → Engine → trả kết quả.
- **Storage Engine**: Handler API (ha_open, ha_index_read, ha_write_row...); InnoDB (mặc định), MyISAM, MEMORY; mỗi bảng chọn engine riêng.
- **InnoDB vs MyISAM**: InnoDB có ACID, row lock, MVCC, crash recovery; MyISAM chỉ table lock, không transaction.

**Topic**: 1.1 Server Architecture → 1.2 Client Protocol → 1.3 Thread Model → 1.4 Query Execution Flow → 1.5 Storage Engine → 1.6 InnoDB vs MyISAM.
