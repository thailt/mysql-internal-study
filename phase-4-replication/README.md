# Phase 4: Replication & High Availability

Understand MySQL replication internals, binary log mechanics, and high availability architectures.

> Each topic below is **self-contained**. Jump into any item freely — prerequisites are noted where needed.

## Topic Map

```
┌─────────────────────────────────────────────────────┐
│              4.1 Binary Log                          │
│    (SBR/RBR, GTID, binlog events, rotation)         │
├─────────────────────────────────────────────────────┤
│              4.2 Replication Topology                │
│    (async, semi-sync, multi-source, lag)             │
├─────────────────────────────────────────────────────┤
│              4.3 InnoDB Cluster / Group Replication  │
│    (Paxos, Router, failover, consistency levels)     │
├─────────────────────────────────────────────────────┤
│              4.4 Backup & Recovery                   │
│    (logical, physical, PITR, CLONE plugin)           │
└─────────────────────────────────────────────────────┘
```

---

## 4.1 Binary Log

**Goal**: Understand MySQL's binary log format, GTID, and how it enables replication and point-in-time recovery.

**Key Concepts**:
- **Binary log (binlog)**: ordered sequence of events describing data changes. Foundation for replication and PITR
- **Formats**:
  - **Statement-based (SBR)**: logs the SQL statement. Compact but non-deterministic functions (e.g., `NOW()`, `UUID()`) can cause divergence
  - **Row-based (RBR)**: logs actual row changes (before/after images). Deterministic, larger size. Default since 5.7.7
  - **Mixed**: server chooses SBR when safe, RBR otherwise
- **GTID (Global Transaction Identifier)**: `server_uuid:transaction_id`. Enables auto-positioning — replica knows exactly where to resume
- **Binlog events**: `QUERY_EVENT`, `TABLE_MAP_EVENT`, `WRITE_ROWS_EVENT`, `UPDATE_ROWS_EVENT`, `DELETE_ROWS_EVENT`, `XID_EVENT`
- **Rotation**: new binlog file when `max_binlog_size` reached or `FLUSH BINARY LOGS`
- **Purging**: `PURGE BINARY LOGS BEFORE '2024-01-01'` or `binlog_expire_logs_seconds`
- **Two-phase commit**: InnoDB redo log + binlog must be in sync → internal XA transaction

**Lab**:
```sql
-- Binary log configuration
SHOW VARIABLES LIKE 'log_bin%';
SHOW VARIABLES LIKE 'binlog_format';
SHOW VARIABLES LIKE 'binlog_row_image';
SHOW VARIABLES LIKE 'gtid_mode';
SHOW VARIABLES LIKE 'enforce_gtid_consistency';
SHOW VARIABLES LIKE 'max_binlog_size';
SHOW VARIABLES LIKE 'binlog_expire_logs_seconds';

-- List binlog files
SHOW BINARY LOGS;
SHOW MASTER STATUS;

-- View binlog events
SHOW BINLOG EVENTS IN 'mysql-bin.000001' LIMIT 30;

-- Make a change and inspect
INSERT INTO lab.employees (name, department, salary, hire_date)
  VALUES ('Binlog Test', 'QA', 60000, '2024-06-01');

-- See the new events
SHOW BINLOG EVENTS IN 'mysql-bin.000001' FROM 0 LIMIT 50;

-- GTID tracking
SELECT @@gtid_executed\G
SELECT @@gtid_purged\G
```

```bash
# Decode binlog to readable format
docker exec mysql-lab mysqlbinlog --base64-output=DECODE-ROWS -v \
  /var/lib/mysql/mysql-bin.000001 | tail -60

# Binlog file sizes
docker exec mysql-lab ls -lh /var/lib/mysql/mysql-bin.*
```

**Read**:
- [Binary Log Overview](https://dev.mysql.com/doc/refman/8.4/en/binary-log.html)
- [GTID Concepts](https://dev.mysql.com/doc/refman/8.4/en/replication-gtids-concepts.html)
- *High Performance MySQL* Ch.10 — Replication

**Deliverable**: Decode a binlog file using `mysqlbinlog`. Identify each event type and explain the two-phase commit between InnoDB redo log and binlog.

---

## 4.2 Replication Topology

**Goal**: Understand how MySQL replicates data between servers and the trade-offs of each topology.

**Prerequisites**: 4.1 (Binary Log) — replication is built on top of binlog.

**Key Concepts**:
- **Async replication**:
  - Source writes to binlog → replica IO thread reads binlog → writes to relay log → SQL thread applies events
  - **Three threads**: source dump thread, replica IO thread, replica SQL thread
  - **Relay log**: local copy of source's binlog on replica
  - Risk: data loss if source crashes before replica receives events
- **Semi-synchronous replication**:
  - Source waits for at least one replica to ACK before returning to client
  - `AFTER_SYNC` (default 8.0): ACK after binlog write, before storage engine commit → no phantom reads
  - `AFTER_COMMIT`: ACK after commit → possible phantom reads on failover
  - Trade-off: increased latency for stronger durability
- **Multi-source replication**: replica pulls from multiple sources → merges via channels
- **Replication lag**: caused by single-threaded SQL apply (fixed with MTS/parallel replication in 8.0), heavy writes, network, replica hardware
- **Parallel replication** (`replica_parallel_workers`): applies non-conflicting transactions in parallel using LOGICAL_CLOCK or WRITESET

**Lab**:
```sql
-- Replication plugins available
SHOW PLUGINS WHERE Name LIKE '%semi%' OR Name LIKE '%group%';

-- Replication status (on replica)
-- SHOW REPLICA STATUS\G

-- Parallel replication config
SHOW VARIABLES LIKE 'replica_parallel%';

-- Simulate: measure binlog position
SHOW MASTER STATUS;

-- Replication-related metrics
SHOW STATUS LIKE 'Rpl%';
SELECT * FROM performance_schema.replication_connection_status\G
SELECT * FROM performance_schema.replication_applier_status\G
```

**Read**:
- [MySQL Replication](https://dev.mysql.com/doc/refman/8.4/en/replication.html)
- [Semi-Synchronous Replication](https://dev.mysql.com/doc/refman/8.4/en/replication-semisync.html)
- *High Performance MySQL* Ch.10 — Replication Topologies

**Deliverable**: Draw the data flow diagram for async replication (3 threads). Explain when semi-sync `AFTER_SYNC` vs `AFTER_COMMIT` matters during failover.

---

## 4.3 InnoDB Cluster / Group Replication

**Goal**: Understand MySQL's built-in high availability stack and Paxos-based consensus.

**Prerequisites**: 4.2 (Replication Topology) — Group Replication extends traditional replication.

**Key Concepts**:
- **Group Replication**: multi-primary or single-primary mode with Paxos-based consensus
  - Every transaction must be certified (conflict detection) by the group before commit
  - Conflict detection: based on writesets (primary keys modified) — conflicting transactions on different members → first wins
- **InnoDB Cluster** = Group Replication + MySQL Shell + MySQL Router
  - **MySQL Shell**: admin API for cluster management (`dba.createCluster()`, `cluster.addInstance()`)
  - **MySQL Router**: lightweight proxy for read/write splitting and automatic failover
- **Consistency levels**:
  - `EVENTUAL`: no read consistency guarantee (default)
  - `BEFORE_ON_PRIMARY_FAILOVER`: new primary waits for backlog to apply before accepting reads
  - `BEFORE`: reads wait for all preceding transactions to apply
  - `AFTER`: writes wait for all members to apply before returning
- **Flow control**: throttles writers if any member falls too far behind
- **Quorum**: majority of members must agree → 3 members tolerate 1 failure, 5 tolerate 2

**Lab**:
```sql
-- Group Replication variables
SHOW VARIABLES LIKE 'group_replication%';

-- Check if GR plugin is available
SELECT PLUGIN_NAME, PLUGIN_STATUS FROM information_schema.PLUGINS
  WHERE PLUGIN_NAME LIKE 'group_replication';

-- Cluster status (via MySQL Shell)
-- mysqlsh root@localhost:3306
-- dba.checkInstanceConfiguration()

-- Consistency level
SHOW VARIABLES LIKE 'group_replication_consistency';

-- Performance schema tables for GR
SELECT * FROM performance_schema.replication_group_members;
SELECT * FROM performance_schema.replication_group_member_stats\G
```

**Read**:
- [Group Replication](https://dev.mysql.com/doc/refman/8.4/en/group-replication.html)
- [InnoDB Cluster](https://dev.mysql.com/doc/mysql-shell/8.4/en/mysql-innodb-cluster.html)
- [MySQL Router](https://dev.mysql.com/doc/mysql-router/8.4/en/)

**Deliverable**: Draw the InnoDB Cluster architecture (3 nodes + Router). Explain the transaction certification flow in Group Replication.

---

## 4.4 Backup & Recovery

**Goal**: Understand backup strategies, their trade-offs, and how to perform point-in-time recovery.

**Prerequisites**: 4.1 (Binary Log) — PITR depends on binlog.

**Key Concepts**:
- **Logical backup**: SQL-level dump (human-readable, portable, slow for large datasets)
  - `mysqldump`: single-threaded, `--single-transaction` for consistent InnoDB backup without locking
  - `mysqlpump`: parallel dump (deprecated in 8.0.34+)
  - `mysql-shell` `util.dumpInstance()`: parallel, compressed, compatible with MySQL Database Service
- **Physical backup**: file-level copy (fast, but tied to MySQL version and OS)
  - **Percona XtraBackup**: hot backup with redo log capture, supports incremental
  - **MySQL Enterprise Backup**: official Oracle tool
- **CLONE plugin** (8.0.17+): physical snapshot from a running instance over the network — ideal for provisioning replicas
- **Point-in-time recovery (PITR)**: restore full backup → replay binlog from backup position to target timestamp
- **Backup strategy**: full weekly + incremental daily + continuous binlog archiving
- **`--single-transaction`** vs **`--lock-all-tables`**: InnoDB vs MyISAM trade-off

**Lab**:
```sql
-- CLONE plugin
INSTALL PLUGIN clone SONAME 'mysql_clone.so';
SELECT PLUGIN_NAME, PLUGIN_STATUS FROM information_schema.PLUGINS WHERE PLUGIN_NAME = 'clone';
```

```bash
# Logical backup with mysqldump
docker exec mysql-lab mysqldump -u root -prootpass \
  --single-transaction --routines --triggers --events \
  lab > /tmp/lab_backup.sql

# Inspect the dump
head -50 /tmp/lab_backup.sql

# Backup specific tables
docker exec mysql-lab mysqldump -u root -prootpass \
  --single-transaction lab employees orders > /tmp/lab_tables.sql

# MySQL Shell parallel dump (if mysql-shell installed)
# mysqlsh root@localhost:3306 -- util.dumpInstance('/tmp/full_dump')

# Point-in-time recovery workflow:
# 1. Restore full backup
# docker exec -i mysql-lab mysql -u root -prootpass lab < /tmp/lab_backup.sql
# 2. Find target position in binlog
# docker exec mysql-lab mysqlbinlog --start-datetime="2024-01-01 00:00:00" \
#   --stop-datetime="2024-06-15 12:00:00" /var/lib/mysql/mysql-bin.000001
# 3. Apply binlog events
# docker exec mysql-lab mysqlbinlog --stop-datetime="2024-06-15 12:00:00" \
#   /var/lib/mysql/mysql-bin.000001 | docker exec -i mysql-lab mysql -u root -prootpass
```

**Read**:
- [mysqldump](https://dev.mysql.com/doc/refman/8.4/en/mysqldump.html)
- [MySQL CLONE Plugin](https://dev.mysql.com/doc/refman/8.4/en/clone-plugin.html)
- [Point-in-Time Recovery](https://dev.mysql.com/doc/refman/8.4/en/point-in-time-recovery.html)
- *High Performance MySQL* Ch.11 — Backup and Recovery

**Deliverable**: Perform a full backup + PITR exercise: backup, make changes, then recover to a specific point in time. Document each step.

---

## Progress Tracker

| # | Topic | Status |
|---|-------|--------|
| 4.1 | Binary Log | [ ] |
| 4.2 | Replication Topology | [ ] |
| 4.3 | InnoDB Cluster / Group Replication | [ ] |
| 4.4 | Backup & Recovery | [ ] |
