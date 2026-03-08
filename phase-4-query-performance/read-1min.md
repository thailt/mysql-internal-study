# Phase 4: Replication & High Availability — 1 phút

**Mục tiêu**: Hiểu replication, binary log và kiến trúc high availability.

- **Binary Log (4.1)**: Chuỗi event thay đổi dữ liệu; SBR/RBR/Mixed; GTID (server_uuid:tx_id); rotation, purge; two-phase commit (redo + binlog).
- **Replication Topology (4.2)**: Async (source dump → replica IO → relay log → SQL thread); semi-sync (đợi ACK); multi-source; lag; parallel replication (replica_parallel_workers).
- **InnoDB Cluster / Group Replication (4.3)**: Paxos; Group Replication + MySQL Shell + Router; consistency levels (EVENTUAL, BEFORE, AFTER); flow control; quorum.
- **Backup & Recovery (4.4)**: Logical (mysqldump, mysqlpump, util.dumpInstance); physical (XtraBackup, MEB); CLONE plugin; PITR (full + replay binlog).

**Topic**: 4.1 Binary Log → 4.2 Replication Topology → 4.3 InnoDB Cluster / Group Replication → 4.4 Backup & Recovery.
