# MySQL Internals Deep Dive

A structured, hands-on learning plan to deeply understand MySQL internals — targeting System Architect / Staff Engineer level knowledge.

## Project Structure

```
.
├── README.md
├── docker/                          # Lab environment
│   ├── docker-compose.yml           # MySQL 8.4 container
│   ├── conf/my.cnf                  # Custom MySQL config
│   ├── init/01-sample-data.sql      # Seed data (employees, orders)
│   └── README.md                    # Lab usage guide
├── phase-1-architecture/            # Week 1–2
├── phase-2-innodb/                  # Week 3–5
├── phase-3-query-optimization/      # Week 6–7
├── phase-4-replication/             # Week 8–9
└── phase-5-performance/             # Week 10
```

## Lab Environment

MySQL 8.4.3 running in Docker with `performance_schema` and InnoDB monitors enabled.

```bash
cd docker && docker compose up -d
docker exec -it mysql-lab mysql -u root -prootpass lab
```

See [docker/README.md](docker/README.md) for details.

## Learning Roadmap (~10 weeks)

### Phase 1: Architecture Foundation (Week 1–2)

| # | Topic | Key Concepts |
|---|-------|-------------|
| 1 | MySQL Server Architecture | Client/Server model, connection handling, thread pool |
| 2 | Query Execution Flow | Parser → Optimizer → Executor → Storage Engine |
| 3 | Storage Engine Layer | Pluggable architecture, handler interface |
| 4 | InnoDB vs MyISAM | Trade-offs, why InnoDB is default since 5.5 |

### Phase 2: InnoDB Deep Dive (Week 3–5)

| # | Topic | Key Concepts |
|---|-------|-------------|
| 1 | Buffer Pool | Page management, LRU algorithm, dirty page flushing |
| 2 | B+ Tree Index | Clustered index, secondary index, index merge |
| 3 | Transaction & MVCC | Undo log, read view, snapshot isolation |
| 4 | Locking | Row lock, gap lock, next-key lock, deadlock detection |
| 5 | Redo Log & WAL | Crash recovery, checkpoint, doublewrite buffer |

### Phase 3: Query Optimization (Week 6–7)

| # | Topic | Key Concepts |
|---|-------|-------------|
| 1 | Query Optimizer | Cost-based optimization, join algorithms (NLJ, Hash Join, BKA) |
| 2 | Execution Plan | `EXPLAIN ANALYZE`, key metrics, index selection |
| 3 | Index Strategy | Covering index, composite index, index condition pushdown |
| 4 | Query Rewrite | Subquery optimization, semi-join, materialization |

### Phase 4: Replication & High Availability (Week 8–9)

| # | Topic | Key Concepts |
|---|-------|-------------|
| 1 | Binary Log | Row-based vs Statement-based, GTID |
| 2 | Replication Topology | Async, semi-sync, group replication |
| 3 | InnoDB Cluster | Router, failover, consistency levels |
| 4 | Backup & Recovery | Physical vs logical, point-in-time recovery |

### Phase 5: Performance & Production (Week 10)

| # | Topic | Key Concepts |
|---|-------|-------------|
| 1 | Performance Schema | Instrumentation, wait analysis, sys schema |
| 2 | Memory Architecture | Global buffers, session buffers, tuning |
| 3 | I/O Optimization | Tablespace, page size, compression |
| 4 | Troubleshooting | Slow query, lock contention, replication lag |

## References

| Source | Focus |
|---|---|
| *High Performance MySQL* (4th Ed) | Comprehensive, production-focused |
| [MySQL Internals Manual](https://dev.mysql.com/doc/dev/mysql-server/latest/) | Official architecture docs |
| [mysql/mysql-server](https://github.com/mysql/mysql-server) | InnoDB source code |
| [Jeremy Cole's blog](https://blog.jcole.us/innodb/) | B+ Tree, page structure |
| [Percona Blog](https://www.percona.com/blog/) | Real-world performance tuning |

## Current Status

- [x] Project initialized
- [x] Docker lab running (MySQL 8.4.3, verified)
- [ ] Phase 1: Architecture Foundation
- [ ] Phase 2: InnoDB Deep Dive
- [ ] Phase 3: Query Optimization
- [ ] Phase 4: Replication & High Availability
- [ ] Phase 5: Performance & Production
