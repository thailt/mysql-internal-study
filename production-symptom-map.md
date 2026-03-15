# Production Symptom Map

Bridge MySQL internals to production diagnosis.

| Symptom | Likely internal causes | What to inspect | Possible actions |
|---|---|---|---|
| Query suddenly slow | bad plan, stale stats, missing index, lock wait | `EXPLAIN ANALYZE`, `OPTIMIZER_TRACE`, `sys.statement_analysis`, lock waits | analyze table, add/fix index, rewrite SQL, reduce contention |
| Throughput drops under concurrency | lock contention, deadlocks, hot rows, long transactions | `SHOW ENGINE INNODB STATUS`, `performance_schema.data_locks`, trx views | reduce transaction scope, change access pattern, tune retries |
| High read latency | buffer pool misses, random I/O, poor access path | buffer pool stats, file I/O views, plan analysis | tune indexes, enlarge buffer pool, reduce scans |
| Commit latency spikes | redo flush pressure, fsync cost, checkpoint pressure | redo/checkpoint metrics, log status | tune log settings carefully, improve storage, reduce burstiness |
| Replica lag grows | slow apply, large transactions, I/O bottleneck, insufficient parallelism | replication status, applier worker stats, source transaction pattern | enable/tune parallel apply, reduce large transactions, improve I/O |
| Memory pressure | oversized global buffers, too many connections, large session buffers | memory views, `max_connections`, buffer config | right-size buffers, cap concurrency, tune app pool |
| App sees deadlocks/timeouts | write conflicts, range locks, transaction order mismatch | InnoDB status, lock waits, SQL pattern review | reorder writes consistently, shrink transactions, better indexes |
| Recovery takes long after crash | large checkpoint age, large undo/redo work, long transactions | redo/checkpoint age, recovery logs, transaction footprint | reduce checkpoint lag, avoid long-running transactions |

## Use pattern
For every performance/consistency problem, try to map:

```text
symptom
  -> probable mechanism
  -> exact signal to inspect
  -> safest mitigation first
```
