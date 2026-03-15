# MySQL Internals Cheatsheet

## Mental model
- `mysqld` = server process
- SQL layer = parser + optimizer + executor
- storage engine = where data is actually stored/accessed
- handler API = bridge between SQL layer and engine

## Storage
- buffer pool = page cache in RAM
- page = basic I/O unit
- clustered index = primary key tree holds row data
- secondary index = key -> primary key
- bookmark lookup = secondary lookup + clustered lookup

## Concurrency
- MVCC = snapshot reads without blocking writes in many cases
- undo log = old versions + rollback support
- read view = visibility rule for snapshot reads
- gap/next-key locks = prevent phantoms in repeatable-read semantics
- deadlock = circular wait; engine picks a victim

## Durability
- WAL = log first, data page later
- redo log = crash recovery for committed changes
- LSN = position in redo stream
- checkpoint = point up to which dirty pages are safely flushed
- doublewrite = torn-page protection

## Optimizer / performance
- optimizer = cost-based plan chooser
- EXPLAIN = estimated plan
- EXPLAIN ANALYZE = actual execution behavior
- covering index = all needed columns in index
- sargable predicate = predicate the optimizer can use with index efficiently

## Scale / ops
- redo log != binlog
- redo log = local crash recovery
- binlog = change propagation / replication / PITR
- GTID = global transaction identity for replication positioning
- replication != backup

## One-line chain
```text
storage -> concurrency -> durability -> optimizer -> tuning -> scale/ops
```
