# Phase 4: Replication & High Availability — Full content

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

**Goal**: Binlog format, GTID, replication and PITR.

**Key Concepts**: Binlog formats (SBR, RBR, Mixed); GTID; events (QUERY, TABLE_MAP, WRITE/UPDATE/DELETE_ROWS, XID); rotation and purge; two-phase commit (redo + binlog).

**Lab**: Full SQL and bash from Phase 4 README (log_bin*, binlog_format, gtid_mode, SHOW BINARY LOGS, SHOW BINLOG EVENTS, INSERT + inspect, mysqlbinlog decode).

**Read**: Binary Log, GTID Concepts, *High Performance MySQL* Ch.10.

**Deliverable**: Decode a binlog with mysqlbinlog; identify event types; explain two-phase commit.

---

## 4.2 Replication Topology

**Goal**: How data replicates and trade-offs of each topology.

**Key Concepts**: Async (3 threads, relay log, risk); semi-sync (AFTER_SYNC vs AFTER_COMMIT); multi-source; lag causes; parallel replication (replica_parallel_workers).

**Lab**: Plugins; REPLICA STATUS; replica_parallel_*; replication_connection_status, replication_applier_status.

**Read**: MySQL Replication, Semi-Synchronous Replication, *High Performance MySQL* Ch.10.

**Deliverable**: Draw async replication data flow (3 threads); explain when AFTER_SYNC vs AFTER_COMMIT matters at failover.

---

## 4.3 InnoDB Cluster / Group Replication

**Goal**: Built-in HA stack and Paxos-based consensus.

**Key Concepts**: Group Replication (certification, writeset conflict); InnoDB Cluster (Shell + Router); consistency levels; flow control; quorum.

**Lab**: group_replication* variables; PLUGINS; consistency; replication_group_members, replication_group_member_stats.

**Read**: Group Replication, InnoDB Cluster, MySQL Router.

**Deliverable**: Draw InnoDB Cluster (3 nodes + Router); explain transaction certification flow.

---

## 4.4 Backup & Recovery

**Goal**: Backup strategies, trade-offs, and PITR.

**Key Concepts**: Logical (mysqldump, util.dumpInstance); physical (XtraBackup, MEB); CLONE plugin; PITR; --single-transaction vs --lock-all-tables.

**Lab**: CLONE plugin; mysqldump --single-transaction; PITR steps (restore, binlog position, apply).

**Read**: mysqldump, CLONE Plugin, Point-in-Time Recovery, *High Performance MySQL* Ch.11.

**Deliverable**: Full backup + PITR exercise; document each step.

---

## Progress Tracker

| # | Topic | Status |
|---|-------|--------|
| 4.1 | Binary Log | [ ] |
| 4.2 | Replication Topology | [ ] |
| 4.3 | InnoDB Cluster / Group Replication | [ ] |
| 4.4 | Backup & Recovery | [ ] |
