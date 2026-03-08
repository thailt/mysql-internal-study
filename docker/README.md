# Docker Lab Environment

MySQL 8.4.3 lab container with `performance_schema`, InnoDB monitors, and sample data pre-loaded.

## Quick Start

```bash
cd docker
docker compose up -d
```

## Connect

```bash
docker exec -it mysql-lab mysql -u root -prootpass lab
```

## Container Details

| Property | Value |
|---|---|
| Container name | `mysql-lab` |
| Image | `mysql:8.4` (verified 8.4.3) |
| Port | `3306` |
| Root password | `rootpass` |
| Default database | `lab` |

## Custom Configuration (`conf/my.cnf`)

| Setting | Value | Used in |
|---|---|---|
| `innodb_buffer_pool_size` | 256M | Phase 2 |
| `general_log` | ON | Phase 1 |
| `slow_query_log` | ON (> 1s) | Phase 3, 5 |
| `log_bin` / `binlog_format` | ROW | Phase 4 |
| `performance-schema` | ON (via cmd) | Phase 5 |
| `innodb-monitor-enable` | all (via cmd) | Phase 2 |

## Sample Data (`init/01-sample-data.sql`)

**employees** — 5 rows, indexes on `department`, `salary`, `hire_date`

**orders** — empty, FK to employees, indexes on `employee_id`, `status`, `order_date`

## Useful Queries by Phase

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

## Lifecycle

```bash
docker compose ps             # check status
docker compose logs -f        # follow logs
docker compose down           # stop, keep data
docker compose down -v        # stop, remove data
```
