# Phase 4: Replication & High Availability — 10 phút

## Mục tiêu
Hiểu replication, binary log và kiến trúc HA. Các topic self-contained.

---

## 4.1 Binary Log
- **Binary log**: chuỗi event mô tả thay đổi dữ liệu; cơ sở cho replication và PITR.
- **Format**: **SBR** — log câu SQL; gọn nhưng hàm không deterministic (NOW(), UUID()) có thể gây replica lệch. **RBR** — log thay đổi từng dòng (before/after); deterministic, mặc định từ 5.7.7. **Mixed**: server chọn SBR khi an toàn.
- **GTID**: server_uuid:transaction_id; replica biết chính xác vị trí resume (auto-positioning). **Events**: QUERY_EVENT, TABLE_MAP_EVENT, WRITE_ROWS_EVENT, UPDATE_ROWS_EVENT, DELETE_ROWS_EVENT, XID_EVENT.
- **Rotation**: file mới khi max_binlog_size hoặc FLUSH BINARY LOGS. **Purge**: PURGE BINARY LOGS BEFORE 'date' hoặc binlog_expire_logs_seconds. **Two-phase commit**: InnoDB redo + binlog phải đồng bộ (XA nội bộ).

**Lab**: log_bin, binlog_format, binlog_row_image, gtid_mode, enforce_gtid_consistency, max_binlog_size, binlog_expire_logs_seconds; SHOW BINARY LOGS, SHOW MASTER STATUS; SHOW BINLOG EVENTS IN '...' LIMIT 30; INSERT vào lab.employees rồi xem event mới; @@gtid_executed, @@gtid_purged; mysqlbinlog --base64-output=DECODE-ROWS -v; ls mysql-bin.*.

---

## 4.2 Replication Topology
- **Async**: source ghi binlog → replica IO thread đọc binlog → ghi relay log → SQL thread apply. **Ba thread**: source dump, replica IO, replica SQL. **Relay log**: bản copy binlog trên replica. Rủi ro: mất dữ liệu nếu source crash trước khi replica nhận event.
- **Semi-sync**: source đợi ít nhất 1 replica ACK. **AFTER_SYNC** (mặc định 8.0): ACK sau ghi binlog, trước commit storage → không phantom read khi failover. **AFTER_COMMIT**: ACK sau commit → có thể phantom.
- **Multi-source**: replica kéo từ nhiều source (channels). **Replication lag**: single-threaded SQL apply (giảm bằng parallel replication 8.0), ghi nặng, mạng, phần cứng replica. **Parallel replication**: replica_parallel_workers; LOGICAL_CLOCK hoặc WRITESET.

**Lab**: SHOW PLUGINS (semi, group); SHOW REPLICA STATUS (trên replica); replica_parallel_*; SHOW MASTER STATUS; Rpl_* status; replication_connection_status, replication_applier_status.

---

## 4.3 InnoDB Cluster / Group Replication
- **Group Replication**: multi-primary hoặc single-primary; consensus Paxos. Mỗi transaction phải được certify (conflict detection); conflict theo writeset (PK đã sửa) — transaction sau conflict bị từ chối.
- **InnoDB Cluster** = Group Replication + MySQL Shell + MySQL Router. **MySQL Shell**: dba.createCluster(), cluster.addInstance(). **MySQL Router**: proxy, read/write split, failover tự động.
- **Consistency levels**: EVENTUAL (mặc định); BEFORE_ON_PRIMARY_FAILOVER; BEFORE (đọc đợi apply); AFTER (ghi đợi apply toàn bộ). **Flow control**: throttle writer nếu member chậm. **Quorum**: đa số member — 3 node chịu 1 lỗi, 5 chịu 2.

**Lab**: group_replication* variables; PLUGINS (group_replication); group_replication_consistency; replication_group_members, replication_group_member_stats; MySQL Shell dba.checkInstanceConfiguration().

---

## 4.4 Backup & Recovery
- **Logical backup**: SQL (mysqldump — single-threaded; --single-transaction cho InnoDB consistent không lock); mysqlpump (parallel, deprecated 8.0.34+); mysql-shell util.dumpInstance() (parallel, nén).
- **Physical backup**: file-level (XtraBackup, MEB) — nhanh, gắn version/OS. **CLONE plugin** (8.0.17+): snapshot vật lý từ instance đang chạy qua mạng — dùng cho tạo replica nhanh.
- **PITR**: restore full backup → replay binlog từ vị trí backup đến thời điểm cần. Chiến lược: full định kỳ + incremental + binlog liên tục. --single-transaction vs --lock-all-tables (InnoDB vs MyISAM).

**Lab**: INSTALL PLUGIN clone; mysqldump --single-transaction --routines --triggers --events lab; backup bảng; PITR: restore full, tìm vị trí trong binlog (mysqlbinlog --start/stop-datetime), apply binlog.

---

## Tóm tắt
Binlog (format, GTID, two-phase commit) → Async/Semi-sync (3 threads, relay, lag, parallel) → Group Replication + Router (Paxos, certify, consistency) → Backup (logical/physical, CLONE) + PITR.
