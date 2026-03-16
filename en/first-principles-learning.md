# MySQL from First Principles

Learn from underlying constraints first, then derive each mechanism. Start not with “what is the buffer pool?”, but with “what problems must a database engine solve, and why does something like a buffer pool become necessary?”

## How to use this file
This is the English first-principles entrypoint.

Suggested order:
1. [README](README.md)
2. [roadmap-v2.md](../roadmap-v2.md)
3. this file
4. current phase README
5. that phase's reading ladder (`read-1min` -> `read-full`)

## Principle 0: System and boundaries
A `mysqld` process has to handle connections, SQL, execution coordination, and interaction with storage engines. SQL is the logical layer; the engine is where data is actually accessed and persisted.

Implications:
1. distinguish the SQL layer from the storage engine layer
2. understand the handler API as the boundary
3. know the end-to-end path: client -> parser -> optimizer -> executor -> handler -> engine

Mapped phase: `../phase-0-system-boundaries/`

## Principle 1: Storage — disk is slow, RAM is fast
Direct row-by-row disk access is impractical. A database needs page-oriented I/O, an in-memory page cache, and structures that help find pages efficiently.

Implications:
1. page/block as the unit of I/O
2. buffer pool as RAM cache
3. B+ tree as a practical lookup structure
4. clear distinction between clustered and secondary indexes

Mapped phase: `../phase-1-storage/`

## Principle 2: Concurrency — many actors share one dataset
If everything is locked all the time, throughput collapses. If nothing is coordinated, correctness collapses.

Implications:
1. transaction boundaries
2. isolation / visibility rules
3. MVCC for snapshot reads
4. undo log and read view
5. record / gap / next-key locks for write and range coordination
6. deadlock detection as a normal need

Mapped phase: `../phase-2-concurrency/`

## Principle 3: Durability — commit must survive a crash
RAM is volatile. Flushing data pages on every commit is too expensive.

Implications:
1. write-ahead logging
2. redo log for committed changes
3. LSN and checkpoint to track durable progress
4. doublewrite for page integrity
5. recovery = redo committed work + undo incomplete work

Mapped phase: `../phase-3-durability/`

## Principle 4: Execution plan choice
A single SQL statement may have many valid plans with wildly different costs.

Implications:
1. a cost-based optimizer
2. statistics/cardinality for plan evaluation
3. join order as a first-class decision
4. ability to read `EXPLAIN`, `EXPLAIN ANALYZE`, and when needed `optimizer trace`

Mapped phase: `../phase-4-optimizer/`

## Principle 5: Tuning — “slow” is a symptom, not a diagnosis
Slow behavior can come from plan choice, locking, I/O, CPU, memory, or workload shape.

Implications:
1. classify the bottleneck first
2. connect symptom -> mechanism -> evidence -> smallest safe change
3. separate plan issues from contention issues
4. measure before and after

Mapped phase: `../phase-5-performance-tuning/`

## Principle 6: Scale / HA / operations
A single server has limits in capacity, availability, recovery, and observability.

Implications:
1. distinguish redo log from binlog
2. understand async vs semi-sync trade-offs
3. remember replication is not backup
4. have backup + PITR
5. have observability and runbooks

Mapped phase: `../phase-6-replication-ha-ops/`

## Backbone to remember
```text
System
-> Storage
-> Concurrency
-> Durability
-> Optimizer
-> Performance Tuning
-> Replication / HA / Operations
```
