# MySQL Internals Deep Dive

A first-principles, hands-on learning plan to deeply understand MySQL internals — targeting System Architect / Staff Engineer level knowledge.

## First Principles Approach

Instead of studying components in isolation, this plan follows **constraint chains** — each phase starts from a fundamental physical constraint and derives the engineering solutions that follow from it.

```
Physical reality                    Engineering consequence
─────────────────                   ──────────────────────
Disk is 1000x slower than RAM   →  Phase 2: Storage & Durability
Memory is lost on crash         ↗

Multiple users hit same data    →  Phase 3: Concurrency & Isolation

Need to find 1 row in millions  →  Phase 4: Query Performance

Single server has limits        →  Phase 5: Scale, HA & Production
```

## Project Structure

```
.
├── README.md
├── docker/                            # Lab environment
│   ├── docker-compose.yml             # MySQL 8.4 container
│   ├── conf/my.cnf                    # Custom MySQL config
│   ├── init/01-sample-data.sql        # Seed data
│   └── README.md                      # Lab usage guide
├── phase-1-architecture/              # Week 1–2: The Big Picture
├── phase-2-storage-durability/        # Week 3–5: The Disk Problem
├── phase-3-concurrency/               # Week 6–7: The Concurrency Problem
├── phase-4-query-performance/         # Week 8–9: The Search Problem
└── phase-5-scale-production/          # Week 10+: The Scale Problem
```

## Lab Environment

MySQL 8.4.3 running in Docker with `performance_schema` and InnoDB monitors enabled.

```bash
cd docker && docker compose up -d
docker exec -it mysql-lab mysql -u root -prootpass lab
```

See [docker/README.md](docker/README.md) for details.

## Learning Roadmap (~10 weeks)

### Phase 1: The Big Picture (Week 1–2)

> *Before solving problems, understand the machine.*

| # | Topic | Key Concepts |
|---|-------|-------------|
| 1.1 | Server Architecture | `mysqld` process, subsystems, memory areas |
| 1.2 | Client Protocol | Handshake, COM_QUERY, connection lifecycle |
| 1.3 | Thread Model | Thread-per-connection, background threads |
| 1.4 | Query Execution Flow | Parser → Optimizer → Executor → Storage Engine |
| 1.5 | Storage Engine Layer | Handler API, pluggable architecture |
| 1.6 | InnoDB vs MyISAM | Trade-offs, why InnoDB won |

### Phase 2: The Disk Problem (Week 3–5)

> *Disk is 1000x slower than memory, and memory is volatile. How do we build a fast, durable database?*

| # | Topic | Constraint → Solution |
|---|-------|----------------------|
| 2.1 | Page I/O & Buffer Pool | Disk slow → cache pages in RAM, LRU eviction |
| 2.2 | B+ Tree & Data Organization | Need fast lookup → tree where node = page = 1 I/O |
| 2.3 | Write-Ahead Logging & Redo Log | Memory volatile → log changes before flush (WAL) |
| 2.4 | Checkpoint, Doublewrite & Crash Recovery | Redo log finite → checkpoint; torn pages → doublewrite |

### Phase 3: The Concurrency Problem (Week 6–7)

> *Multiple users reading and writing the same data. How do we keep everyone correct without killing performance?*

| # | Topic | Constraint → Solution |
|---|-------|----------------------|
| 3.1 | Isolation Levels & The Concurrency Spectrum | Concurrent access → define correctness trade-offs |
| 3.2 | Locking — Writer Safety | Writers conflict → row/gap/next-key locks, deadlock detection |
| 3.3 | MVCC — Reader Freedom | Readers block on locks → keep old versions, lock-free reads |
| 3.4 | Transaction Lifecycle | Putting it together: begin → read/write → commit/rollback |

### Phase 4: The Search Problem (Week 8–9)

> *Finding specific data among millions of rows must be fast. How does the optimizer choose the best path?*

| # | Topic | Constraint → Solution |
|---|-------|----------------------|
| 4.1 | How the Optimizer Thinks | Many possible plans → cost-based selection |
| 4.2 | Reading Execution Plans | Can't optimize blind → EXPLAIN ANALYZE |
| 4.3 | Index Strategy | Full scan too slow → composite, covering, ICP |
| 4.4 | Query Rewrite & Anti-Patterns | Bad SQL can't be fixed by optimizer → sargable predicates |

### Phase 5: The Scale Problem (Week 10+)

> *A single server has limits in capacity, availability, and observability. How do we go beyond?*

| # | Topic | Constraint → Solution |
|---|-------|----------------------|
| 5.1 | Binary Log & Change Propagation | Need to share changes → binlog, GTID, two-phase commit |
| 5.2 | Replication & High Availability | Single point of failure → async/semi-sync, Group Replication |
| 5.3 | Backup & Recovery | Data loss risk → logical/physical backup, PITR |
| 5.4 | Observability & Troubleshooting | Can't fix what you can't see → Performance Schema, sys schema |

## The Constraint Chain

Every InnoDB design decision can be derived from a few physical constraints:

```
Disk is slow (100μs SSD, 10ms HDD vs 100ns RAM)
  → Cache in RAM: Buffer Pool
    → RAM is limited → eviction policy: LRU with midpoint insertion
    → Modify in RAM → dirty pages
      → Dirty pages lost on crash → Write-Ahead Logging (Redo Log)
        → Redo log is finite → Checkpoint (flush dirty, reclaim log)
        → Half-written page on crash → Doublewrite Buffer
  → Organize for fast lookup: B+ Tree
    → Node = page = 1 disk I/O → minimizes reads
    → PK = data (clustered index) → 1 lookup for full row
    → Secondary index stores PK → bookmark lookup (2 lookups)

Multiple concurrent users
  → Writers conflict → Locking (row, gap, next-key)
    → Circular wait → Deadlock detection (wait-for graph)
  → Readers blocked by locks → MVCC (lock-free reads)
    → Old versions needed → Undo Log
    → Which version to see? → Read View + visibility rules
    → Old versions accumulate → Purge Thread

Single server limits
  → Share changes → Binary Log
    → Deterministic → Row-Based Replication
    → Redo log + binlog consistency → Two-Phase Commit (XA)
  → Server dies → Replication + automatic failover
  → Data corruption → Backup + Point-in-Time Recovery
```

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
- [ ] Phase 1: The Big Picture
- [ ] Phase 2: The Disk Problem
- [ ] Phase 3: The Concurrency Problem
- [ ] Phase 4: The Search Problem
- [ ] Phase 5: The Scale Problem
