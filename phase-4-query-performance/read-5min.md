# Phase 4: Replication & High Availability — 5 phút

## Mục tiêu
Hiểu replication, binary log và kiến trúc HA. Các topic self-contained.

---

## 4.1 Binary Log
- **Binlog**: chuỗi event mô tả thay đổi dữ liệu; nền tảng replication và PITR.
- **Format**: **SBR** (log câu SQL — gọn nhưng NOW(), UUID() có thể gây lệch); **RBR** (log thay đổi từng dòng — deterministic, mặc định từ 5.7.7); **Mixed** (server chọn).
- **GTID**: server_uuid:transaction_id — replica tự định vị resume. Event: QUERY_EVENT, TABLE_MAP_EVENT, WRITE/UPDATE/DELETE_ROWS_EVENT, XID_EVENT.
- **Rotation**: file mới khi đạt max_binlog_size hoặc FLUSH BINARY LOGS. **Purge**: PURGE BINARY LOGS BEFORE ... hoặc binlog_expire_logs_seconds. **Two-phase commit**: redo log + binlog đồng bộ (XA nội bộ).

**Lab nhanh**: SHOW VARIABLES LIKE 'log_bin%|binlog_format|gtid_mode'; SHOW BINARY LOGS; SHOW MASTER STATUS; SHOW BINLOG EVENTS; INSERT rồi xem event; mysqlbinlog --base64-output=DECODE-ROWS -v.

---

## 4.2 Replication Topology
- **Async**: source ghi binlog → replica IO thread đọc → relay log → SQL thread apply. Ba thread: dump (source), IO (replica), SQL (replica). Rủi ro: mất dữ liệu nếu source sập trước khi replica nhận.
- **Semi-sync**: source đợi ít nhất một replica ACK. AFTER_SYNC (mặc định 8.0): ACK sau ghi binlog, trước commit engine — không phantom khi failover. AFTER_COMMIT: ACK sau commit — có thể phantom.
- **Multi-source**: một replica kéo nhiều source (channels). **Lag**: do SQL single-threaded (giảm bằng MTS/parallel), ghi nặng, mạng, phần cứng replica. **Parallel replication**: replica_parallel_workers (LOGICAL_CLOCK, WRITESET).

**Lab nhanh**: SHOW PLUGINS (semi, group); replica_parallel_*; SHOW MASTER STATUS; replication_connection_status, replication_applier_status.

---

## 4.3 InnoDB Cluster / Group Replication
- **Group Replication**: multi-primary hoặc single-primary; consensus Paxos. Mỗi transaction được certify (conflict detection) trước khi commit; conflict theo writeset — transaction sau thua.
- **InnoDB Cluster** = Group Replication + MySQL Shell + MySQL Router. **Shell**: dba.createCluster(), cluster.addInstance(). **Router**: proxy read/write split, failover.
- **Consistency**: EVENTUAL (mặc định); BEFORE_ON_PRIMARY_FAILOVER; BEFORE (đọc đợi apply); AFTER (ghi đợi apply). **Flow control**: giảm ghi nếu member chậm. **Quorum**: đa số member đồng ý — 3 node chịu 1 lỗi, 5 chịu 2.

**Lab nhanh**: group_replication* variables; PLUGINS (group_replication); group_replication_consistency; replication_group_members, replication_group_member_stats.

---

## 4.4 Backup & Recovery
- **Logical**: SQL (mysqldump — single-threaded, --single-transaction cho InnoDB consistent); mysqlpump (parallel, deprecated 8.0.34+); mysql-shell util.dumpInstance() (parallel, nén).
- **Physical**: file-level (XtraBackup, MEB) — nhanh, gắn version/OS. **CLONE plugin** (8.0.17+): snapshot vật lý qua mạng, dùng cho clone replica.
- **PITR**: restore full backup → replay binlog từ vị trí backup đến thời điểm cần. Chiến lược: full định kỳ + incremental + binlog liên tục.

**Lab nhanh**: INSTALL PLUGIN clone; mysqldump --single-transaction --routines --triggers --events; PITR: restore + mysqlbinlog --start/stop-datetime.

---

## Tóm tắt
Binlog (SBR/RBR, GTID) → Async/Semi-sync replication (3 threads, lag, parallel) → Group Replication + Router (Paxos, consistency) → Backup (logical/physical, CLONE) + PITR.
