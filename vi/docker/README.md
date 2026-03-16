# Môi trường lab Docker

Container lab MySQL 8.4.3 với `performance_schema`, InnoDB monitors, và sample data được nạp sẵn.

## Khởi động nhanh

```bash
cd docker
docker compose up -d
```

## Kết nối

```bash
docker exec -it mysql-lab mysql -u root -prootpass lab
```

## Thông tin container

| Thuộc tính | Giá trị |
|---|---|
| Tên container | `mysql-lab` |
| Image | `mysql:8.4` (đã xác minh 8.4.3) |
| Port | `3306` |
| Root password | `rootpass` |
| Database mặc định | `lab` |

## Cấu hình tùy chỉnh (`conf/my.cnf`)

| Thiết lập | Giá trị | Dùng trong |
|---|---|---|
| `innodb_buffer_pool_size` | 256M | Phase 2 |
| `general_log` | ON | Phase 1 |
| `slow_query_log` | ON (> 1s) | Phase 3, 5 |
| `log_bin` / `binlog_format` | ROW | Phase 4 |
| `performance-schema` | ON (qua cmd) | Phase 5 |
| `innodb-monitor-enable` | all (qua cmd) | Phase 2 |

## Dữ liệu mẫu (`init/01-sample-data.sql`)

**employees** — 5 rows, có index trên `department`, `salary`, `hire_date`

**orders** — rỗng, FK tới employees, có index trên `employee_id`, `status`, `order_date`

## Query hữu ích theo phase

### Phase 1 — Architecture

```sql
SHOW VARIABLES LIKE 'version%';
SHOW ENGINES;
SHOW VARIABLES LIKE 'general_log%';
SHOW PROCESSLIST;
SHOW STATUS LIKE 'Threads%';
```

### Phase 2 — InnoDB

```sql
SHOW ENGINE INNODB STATUS\G
SELECT * FROM information_schema.INNODB_BUFFER_POOL_STATS\G
SELECT * FROM information_schema.INNODB_TRX;
SELECT * FROM performance_schema.data_locks;
```

### Phase 3 — Query Optimization

```sql
EXPLAIN ANALYZE SELECT * FROM employees WHERE department = 'Engineering';
SET optimizer_trace = 'enabled=on';
SELECT * FROM employees WHERE salary > 80000;
SELECT * FROM information_schema.OPTIMIZER_TRACE\G
```

### Phase 5 — Performance

```sql
SELECT * FROM sys.statement_analysis LIMIT 10;
SELECT * FROM sys.innodb_buffer_stats_by_table;
SELECT * FROM performance_schema.events_waits_summary_global_by_event_name
  ORDER BY SUM_TIMER_WAIT DESC LIMIT 10;
```

## Vòng đời

```bash
docker compose ps             # kiểm tra trạng thái
docker compose logs -f        # xem log liên tục
docker compose down           # dừng, giữ dữ liệu
docker compose down -v        # dừng, xóa dữ liệu
```
