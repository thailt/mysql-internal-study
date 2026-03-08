# Phase 1: The Big Picture (Week 1–2)

> *Before solving problems, understand the machine.*

Understand how MySQL processes a query end-to-end, from client connection to storage engine I/O. This phase builds the mental model that all subsequent phases depend on.

## First Principle (Nguyên lý 0)

**Hệ thống và ranh giới** — Trước khi tối ưu, phải biết máy chạy thế nào.

- **Hỏi trước khi đọc:** Luồng một câu SQL đi qua những thành phần nào? Tại sao phải tách lớp SQL và storage engine? Handler API giải quyết vấn đề gì?
- **Ánh xạ:** [first-principles-learning.md](../first-principles-learning.md) → Nguyên lý 0. Topic 1.1–1.6 là implementation của bản đồ hệ thống.

## Why This Phase First?

You can't reason about *why* InnoDB has a buffer pool until you understand *where* the storage engine sits in the overall architecture. You can't reason about locking until you understand that the executor calls the storage engine row-by-row via the Handler API.

Phase 1 = the map. Phases 2–5 = zooming into each region.

## Topic Map

```
┌─────────────────────────────────────────────────────┐
│                  1.1 Server Architecture             │
│         (mysqld process, components, memory)         │
├──────────────┬──────────────┬───────────────────────┤
│ 1.2 Client   │ 1.3 Thread   │ 1.4 Query Execution   │
│ Protocol     │ Model        │ Flow                   │
│ (connect,    │ (thread-per- │ (parser → optimizer    │
│  handshake,  │  connection, │  → executor → engine)  │
│  commands)   │  thread pool)│                        │
├──────────────┴──────────────┼───────────────────────┤
│ 1.5 Storage Engine Layer    │ 1.6 InnoDB vs MyISAM  │
│ (handler API, pluggable)    │ (trade-offs, history)  │
└─────────────────────────────┴───────────────────────┘
```

---

## 1.1 Server Architecture (mysqld Process)

**Goal**: Understand what `mysqld` is and its major internal components.

**Key Concepts**:

- `**mysqld`** = single process, multi-threaded. The only server binary — everything runs inside this one process
- **Major subsystems**:
  - **Connection Manager**: authenticates clients, assigns threads, manages connection pool
  - **SQL Layer** (a.k.a. Server Layer): parser, preprocessor, optimizer, executor — engine-independent
  - **Storage Engine Layer**: pluggable data access via Handler API (InnoDB, MyISAM, MEMORY, etc.)
  - **Replication Layer**: binary log writer, replication IO/SQL threads
- **Shared memory areas**:
  - **Buffer pool** (`innodb_buffer_pool_size`): largest consumer, caches InnoDB data and index pages
  - **Table cache** (`table_open_cache`): cached file descriptors for open tables
  - **Thread cache** (`thread_cache_size`): pool of reusable threads for new connections
  - **Table definition cache** (`table_definition_cache`): cached data dictionary metadata
  - **Query cache**: removed in 8.0 (scalability bottleneck due to global mutex)
- **Data dictionary** (8.0+): transactional, InnoDB-based system tables replacing `.frm` files
- **Key directories**: `basedir` (binaries), `datadir` (tablespaces, logs, system tables)

**Lab**:

```sql
SELECT @@version, @@version_comment, @@hostname;
SHOW VARIABLES LIKE 'basedir';
SHOW VARIABLES LIKE 'datadir';
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'table_open_cache';
SHOW VARIABLES LIKE 'thread_cache_size';
SHOW STATUS LIKE 'Uptime';
SHOW STATUS LIKE 'Questions';
```

```bash
docker exec mysql-lab ps aux | grep mysqld
docker exec mysql-lab ls -la /var/lib/mysql/
```

**Read**:

- [MySQL Server Architecture](https://dev.mysql.com/doc/refman/8.4/en/mysqld-server.html)
- *High Performance MySQL* Ch.1

**Deliverable**: Draw a block diagram of mysqld showing all subsystems and shared memory areas. Label the data flow from client to disk.

---

## 1.2 Client Protocol & Connection Lifecycle

**Goal**: Understand how a client talks to MySQL at the wire protocol level.

**Key Concepts**:

- **Transport**: TCP 3306 (remote), Unix socket (local)
- **Handshake flow**: TCP connect → server greeting → client auth → OK/ERR
- **Command phase**: `COM_QUERY` (SQL text), `COM_STMT_PREPARE/EXECUTE` (prepared statements), `COM_QUIT`
- **Result set protocol**: column count → column definitions → rows → OK/EOF
- **Connection states**: `connecting` → `sleep` → `query` / `locked` → `sleep` → `COM_QUIT`
- **Connection limits**: `max_connections`, `wait_timeout`, `Aborted_connects` / `Aborted_clients`
- **Connection pooling** (application side): HikariCP, ProxySQL — reuses connections

**Lab**:

```sql
SHOW PROCESSLIST;
SHOW STATUS LIKE 'Connections';
SHOW STATUS LIKE 'Aborted%';
SHOW VARIABLES LIKE 'max_connections';
SHOW VARIABLES LIKE 'wait_timeout';
SELECT * FROM performance_schema.session_connect_attrs
  WHERE PROCESSLIST_ID = CONNECTION_ID();
SELECT * FROM performance_schema.accounts;
```

**Read**:

- [MySQL Client/Server Protocol](https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_basics.html)

**Deliverable**: Explain the full lifecycle from TCP SYN to COM_QUIT, including which MySQL thread states correspond to each phase.

---

## 1.3 Thread Model

**Goal**: Understand how MySQL handles concurrency internally.

**Key Concepts**:

- **Thread-per-connection** (default): 1 client = 1 OS thread. Simple but ~1MB stack per thread, scales poorly beyond ~5000
- **Thread cache**: disconnected threads return to cache → avoids `pthread_create()` overhead
- **Thread pool** (Enterprise / Percona): fixed worker pool with priority queues
- **Background threads** (InnoDB):
  - **Page cleaner** (`innodb_page_cleaners`): flushes dirty pages
  - **Purge threads** (`innodb_purge_threads`): cleans undo logs
  - **IO threads** (`innodb_read_io_threads`, `innodb_write_io_threads`): async I/O
  - **Log writer**: writes redo log buffer to disk
- **Mutex / rw-lock contention**: visible in `SHOW ENGINE INNODB STATUS` → SEMAPHORES

**Lab**:

```sql
SHOW VARIABLES LIKE 'thread_handling';
SHOW STATUS LIKE 'Threads%';
SELECT NAME, TYPE, THREAD_ID FROM performance_schema.threads
  WHERE TYPE = 'BACKGROUND' ORDER BY NAME;
SELECT THREAD_ID, PROCESSLIST_USER, PROCESSLIST_COMMAND
  FROM performance_schema.threads WHERE TYPE = 'FOREGROUND';
```

**Read**:

- [Thread Handling](https://dev.mysql.com/doc/refman/8.4/en/connection-threads.html)

**Deliverable**: List all background threads and explain each role. Calculate thread cache hit ratio.

---

## 1.4 Query Execution Flow

**Goal**: Trace a SQL statement through every internal layer.

**Key Concepts**:

- **Parser**: SQL text → AST. Catches syntax errors
- **Preprocessor**: semantic validation — table/column existence, permissions
- **Optimizer**: cost-based plan selection — access paths, join order, join algorithm
- **Executor** (8.0+ iterator model): walks iterator tree, calls Handler API
- **Storage Engine**: reads/writes pages via handler interface

```
Client SQL text
  → [Parser]         syntax check → AST
  → [Preprocessor]   semantic check, permissions
  → [Optimizer]      cost-based → execution plan
  → [Executor]       iterator tree → handler calls
  → [Storage Engine] buffer pool → disk I/O
  → [Result Set]     → client
```

**Lab**:

```sql
EXPLAIN FORMAT=TREE SELECT * FROM lab.employees WHERE department = 'Engineering';
EXPLAIN ANALYZE SELECT * FROM lab.employees WHERE department = 'Engineering' AND salary > 80000;
SET optimizer_trace = 'enabled=on';
SELECT * FROM lab.employees WHERE salary > 80000;
SELECT JSON_PRETTY(TRACE) FROM information_schema.OPTIMIZER_TRACE\G
SET optimizer_trace = 'enabled=off';
```

**Read**:

- *High Performance MySQL* Ch.8
- [Optimizer Tracing](https://dev.mysql.com/doc/dev/mysql-server/latest/PAGE_OPT_TRACE.html)

**Deliverable**: Run a JOIN query with optimizer trace. Annotate: table order, access paths, cost comparison, final plan.

---

## 1.5 Storage Engine Layer

**Goal**: Understand how MySQL decouples SQL processing from data storage.

**Key Concepts**:

- **Handler API**: abstract C++ interface (`ha_*` methods) between SQL layer and engines
- **Key operations**: `ha_rnd_init/next` (full scan), `ha_index_init/read/next` (index scan), `ha_write_row`, `ha_update_row`, `ha_delete_row`
- `**handlerton`**: registration struct each engine provides at startup
- **Pluggable**: each table can use a different engine via `ENGINE=xxx`
- **Available engines**: InnoDB (default), MyISAM, MEMORY, CSV, Archive, Blackhole, NDB

**Lab**:

```sql
SHOW ENGINES;
SELECT TABLE_NAME, ENGINE, ROW_FORMAT, TABLE_ROWS FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = 'lab';
FLUSH STATUS;
SELECT * FROM lab.employees WHERE department = 'Engineering';
SHOW STATUS LIKE 'Handler%';
```

**Read**:

- [Storage Engines](https://dev.mysql.com/doc/refman/8.4/en/storage-engines.html)
- Source: `sql/handler.h`

**Deliverable**: Use `FLUSH STATUS` + `Handler%` before/after 3 queries (full scan, index lookup, INSERT). Explain which handler methods were called.

---

## 1.6 InnoDB vs MyISAM

**Goal**: Understand the trade-offs and why InnoDB became the default.

**Key Concepts**:


|                 | InnoDB                      | MyISAM                |
| --------------- | --------------------------- | --------------------- |
| Transactions    | ACID (redo + undo)          | No                    |
| Locking         | Row-level                   | Table-level           |
| Crash recovery  | Automatic (redo log)        | Manual `REPAIR TABLE` |
| Clustered index | PK = data                   | Heap + separate index |
| MVCC            | Readers don't block writers | Shared table lock     |
| Storage         | `.ibd` per table            | `.MYD` + `.MYI`       |


**Why InnoDB won**: crash safety + row locking + MVCC = viable for concurrent OLTP. MyISAM's table-level locking = bottleneck under writes.

**Lab**:

```sql
SHOW ENGINES;
SHOW ENGINE INNODB STATUS\G
SELECT ENGINE, COUNT(*) FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = 'mysql' GROUP BY ENGINE;
```

```bash
docker exec mysql-lab ls -lh /var/lib/mysql/lab/
```

**Read**:

- [InnoDB Introduction](https://dev.mysql.com/doc/refman/8.4/en/innodb-introduction.html)

**Deliverable**: Name 3 scenarios where MyISAM might still be used. Explain why each is increasingly rare.

---

## How It All Fits Together

```
Client connects (TCP 3306)
  → Connection Manager (1.2): handshake, auth, assign thread
  → Thread (1.3): one OS thread per connection
  → SQL text arrives (COM_QUERY)
  → Parser (1.4): SQL → AST
  → Preprocessor (1.4): semantic checks
  → Optimizer (1.4): cost-based plan
  → Executor (1.4): iterator tree → Handler API calls
  → Storage Engine (1.5): InnoDB reads pages from buffer pool / disk
  → Result → client
```

**What's next?** Phase 2 zooms into the storage engine: *why* does InnoDB use pages? *why* a buffer pool? *why* write-ahead logging? All derived from one constraint: **disk is slow**.

---

## Progress Tracker


| #   | Topic                        | Status |
| --- | ---------------------------- | ------ |
| 1.1 | Server Architecture          | [ ]    |
| 1.2 | Client Protocol & Connection | [ ]    |
| 1.3 | Thread Model                 | [ ]    |
| 1.4 | Query Execution Flow         | [ ]    |
| 1.5 | Storage Engine Layer         | [ ]    |
| 1.6 | InnoDB vs MyISAM             | [ ]    |


