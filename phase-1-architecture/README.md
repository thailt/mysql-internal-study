# Phase 1: Architecture Foundation

Understand how MySQL processes a query end-to-end, from client connection to storage engine I/O.

> Each topic below is **self-contained**. Jump into any item freely — prerequisites are noted where needed.

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
- **`mysqld`** = single process, multi-threaded. The only server binary — everything runs inside this one process
- **Major subsystems**:
  - **Connection Manager**: authenticates clients, assigns threads, manages connection pool
  - **SQL Layer** (a.k.a. Server Layer): parser, preprocessor, optimizer, executor — engine-independent
  - **Storage Engine Layer**: pluggable data access via Handler API (InnoDB, MyISAM, MEMORY, etc.)
  - **Replication Layer**: binary log writer, replication IO/SQL threads
- **Shared memory areas**:
  - **Buffer pool** (`innodb_buffer_pool_size`): largest consumer, caches InnoDB data and index pages
  - **Table cache** (`table_open_cache`): cached file descriptors for open tables — avoids repeated file opens
  - **Thread cache** (`thread_cache_size`): pool of reusable threads for new connections
  - **Table definition cache** (`table_definition_cache`): cached `.frm` / data dictionary metadata
  - **Query cache**: removed in 8.0 (scalability bottleneck due to global mutex)
- **Data dictionary** (8.0+): transactional, InnoDB-based system tables replacing `.frm` files
- **Key directories**: `basedir` (binaries), `datadir` (tablespaces, logs, system tables)

**Lab**:
```sql
-- Server identity
SELECT @@version, @@version_comment, @@hostname;
SHOW VARIABLES LIKE 'basedir';
SHOW VARIABLES LIKE 'datadir';

-- Memory-related globals
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'table_open_cache';
SHOW VARIABLES LIKE 'thread_cache_size';
SHOW VARIABLES LIKE 'table_definition_cache';

-- Data dictionary tables (8.0+)
SELECT TABLE_NAME FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = 'mysql' AND TABLE_NAME LIKE 'innodb_%' LIMIT 10;

-- Server uptime and global activity
SHOW STATUS LIKE 'Uptime';
SHOW STATUS LIKE 'Questions';
SHOW STATUS LIKE 'Com_select';
SHOW STATUS LIKE 'Com_insert';
```

```bash
# mysqld process info
docker exec mysql-lab ps aux | grep mysqld

# Data directory structure
docker exec mysql-lab ls -la /var/lib/mysql/
docker exec mysql-lab ls -la /var/lib/mysql/lab/
```

**Read**:
- [MySQL Server Architecture Overview](https://dev.mysql.com/doc/refman/8.4/en/mysqld-server.html)
- [Data Dictionary](https://dev.mysql.com/doc/refman/8.4/en/data-dictionary.html)
- *High Performance MySQL* Ch.1 — MySQL Architecture

**Deliverable**: Draw a block diagram of mysqld showing all subsystems (Connection Manager, SQL Layer, Storage Engine Layer, Replication) and shared memory areas. Label the data flow from client to disk.

---

## 1.2 Client Protocol & Connection Lifecycle

**Goal**: Understand how a client talks to MySQL at the wire protocol level.

**Prerequisites**: 1.1 (Server Architecture) — know what the Connection Manager does.

**Key Concepts**:
- **Transport**: TCP on port 3306 (remote), Unix socket `/var/run/mysqld/mysqld.sock` (local), shared memory (Windows)
- **Handshake flow**:
  1. TCP SYN/ACK → connection established
  2. Server sends **greeting packet**: protocol version, server version, connection ID, auth plugin, capability flags
  3. Client responds: username, auth response, default schema, capability flags
  4. Server sends OK (authenticated) or ERR (rejected)
- **Command phase**: client sends command packets, server responds
  - **COM_QUERY**: execute SQL text
  - **COM_STMT_PREPARE / COM_STMT_EXECUTE**: prepared statements (binary protocol, more efficient)
  - **COM_PING**: health check
  - **COM_QUIT**: close connection gracefully
- **Result set protocol**: column count → column definitions → rows (as text or binary) → OK/EOF
- **Connection states**: `connecting` → `authenticated` → `sleep` (idle) → `query` / `locked` / `sending data` → `sleep` → `COM_QUIT`
- **Connection limits**: `max_connections` (default 151), `wait_timeout` (idle timeout, default 28800s = 8h)
- **Aborted connections**: `Aborted_connects` (auth failures), `Aborted_clients` (client disconnected without COM_QUIT — network issues, timeout)
- **Connection pooling** (application side): HikariCP, ProxySQL, MySQL Router — reuses connections to reduce handshake overhead

**Lab**:
```sql
-- See active connections and their states
SHOW PROCESSLIST;
SHOW FULL PROCESSLIST;
SHOW STATUS LIKE 'Connections';
SHOW STATUS LIKE 'Aborted%';
SHOW VARIABLES LIKE 'max_connections';
SHOW VARIABLES LIKE 'wait_timeout';
SHOW VARIABLES LIKE 'interactive_timeout';

-- Connection attributes (client metadata)
SELECT * FROM performance_schema.session_connect_attrs
  WHERE PROCESSLIST_ID = CONNECTION_ID();

-- Connection ID and user info
SELECT CONNECTION_ID(), CURRENT_USER(), @@hostname;

-- Per-user connection stats
SELECT * FROM performance_schema.accounts;

-- Protocol type of current connection
SHOW STATUS LIKE 'Ssl_cipher';
SELECT @@protocol_version;
```

```bash
# Observe TCP handshake
docker exec mysql-lab mysql -u root -prootpass -e "SELECT 1" --protocol=tcp

# Connection count from OS level
docker exec mysql-lab ss -tnp | grep 3306 | wc -l
```

**Read**:
- [MySQL Client/Server Protocol](https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_basics.html)
- [Connection Management](https://dev.mysql.com/doc/refman/8.4/en/connection-management.html)
- *High Performance MySQL* Ch.1 — Connection Management

**Deliverable**: Explain the full lifecycle of a connection from TCP SYN to COM_QUIT. Include what happens at each step (greeting, auth, command, result set, close) and which MySQL thread states correspond to each phase.

---

## 1.3 Thread Model

**Goal**: Understand how MySQL handles concurrency internally.

**Prerequisites**: 1.1 (Server Architecture), 1.2 (Connection Lifecycle).

**Key Concepts**:
- **Thread-per-connection** (default `thread_handling=one-thread-per-connection`): each client gets a dedicated OS thread. Simple but scales poorly beyond ~5000 connections (context switching, memory overhead ~1MB/thread stack)
- **Thread cache** (`thread_cache_size`): when a client disconnects, the thread goes back to the cache instead of being destroyed. Next connection reuses it → avoids `pthread_create()` overhead
  - Check efficiency: `Threads_created` should be much lower than `Connections`
- **Thread pool** (Enterprise / Percona): fixed pool of worker threads with priority queues. Better for 1000s of concurrent connections with bursty workloads
  - Low-priority queue: new queries
  - High-priority queue: queries already in a transaction (avoids holding locks while waiting)
- **Background threads** (InnoDB):
  - **Master thread**: flushes dirty pages, purges undo logs, merges change buffer (legacy, most work delegated in 8.0)
  - **Page cleaner threads** (`innodb_page_cleaners`): flush dirty pages from buffer pool to disk
  - **Purge threads** (`innodb_purge_threads`): clean up undo logs no longer needed by MVCC
  - **IO threads** (`innodb_read_io_threads`, `innodb_write_io_threads`): async I/O for data pages
  - **Log writer thread**: writes redo log buffer to redo log files
  - **Redo log archiver**, **Clone thread**, **Buffer pool dump/load thread**
- **Mutex / rw-lock contention**: under heavy concurrency, threads compete for shared resources. Visible in `SHOW ENGINE INNODB STATUS` → SEMAPHORES section

**Lab**:
```sql
-- Thread handling model
SHOW VARIABLES LIKE 'thread_handling';
SHOW VARIABLES LIKE 'thread_cache_size';
SHOW VARIABLES LIKE 'thread_stack';

-- Thread status counters
SHOW STATUS LIKE 'Threads%';
-- Threads_cached: in cache, Threads_connected: active,
-- Threads_created: total ever created, Threads_running: executing

-- Thread cache efficiency
SELECT
  (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Threads_created') AS total_created,
  (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Connections') AS total_connections;

-- Background threads (InnoDB)
SELECT NAME, TYPE, THREAD_ID, THREAD_OS_ID FROM performance_schema.threads
  WHERE TYPE = 'BACKGROUND' ORDER BY NAME;

-- Foreground (user) threads
SELECT THREAD_ID, PROCESSLIST_USER, PROCESSLIST_COMMAND, PROCESSLIST_STATE
  FROM performance_schema.threads
  WHERE TYPE = 'FOREGROUND';

-- InnoDB thread configuration
SHOW VARIABLES LIKE 'innodb_read_io_threads';
SHOW VARIABLES LIKE 'innodb_write_io_threads';
SHOW VARIABLES LIKE 'innodb_purge_threads';
SHOW VARIABLES LIKE 'innodb_page_cleaners';

-- Mutex / semaphore contention
SHOW ENGINE INNODB STATUS\G
-- Look for "SEMAPHORES" section
```

**Read**:
- [MySQL Thread Handling](https://dev.mysql.com/doc/refman/8.4/en/connection-threads.html)
- [InnoDB Thread Concurrency](https://dev.mysql.com/doc/refman/8.4/en/innodb-performance-thread-concurrency.html)
- Percona Blog: Thread Pool explained
- *High Performance MySQL* Ch.1 — Concurrency Control

**Deliverable**: List all background threads from `performance_schema.threads` and explain each thread's role. Calculate thread cache hit ratio (`1 - Threads_created/Connections`).

---

## 1.4 Query Execution Flow

**Goal**: Trace a SQL statement through every internal layer.

**Prerequisites**: 1.1 (Server Architecture) — understand the subsystems a query passes through.

**Key Concepts**:
- **Parser**: tokenizes SQL text → builds **Abstract Syntax Tree (AST)**. Catches syntax errors (`ERROR 1064: You have an error in your SQL syntax`)
- **Preprocessor**: semantic validation on the AST
  - Checks table/column existence
  - Resolves aliases, expands `*`
  - Verifies permissions (SELECT privilege, etc.)
- **Optimizer**: cost-based plan selection — the brain of query execution
  - Evaluates access paths: full table scan, index scan, range scan, ref lookup
  - Determines **join order** (which table to read first)
  - Decides on **join algorithm**: Nested Loop Join, Hash Join, BKA
  - Considers subquery strategies: materialization, semi-join, EXISTS rewrite
  - Outputs an **execution plan** (iterator tree in 8.0+)
- **Executor** (8.0+ iterator model): walks the iterator tree top-down
  - Calls `Init()` → `Read()` loop on each iterator
  - Passes rows between iterators (pipelining, no full materialization when possible)
  - Calls storage engine via Handler API for actual data access
- **Storage Engine**: reads/writes data pages. InnoDB returns rows via handler interface
- **Result set**: executor formats rows → sends to client via network protocol

**Flow**:
```
Client SQL text
  → [Parser]         SQL → AST (syntax check)
  → [Preprocessor]   AST validation (semantic check, permissions)
  → [Optimizer]      AST → execution plan (cost-based)
  → [Executor]       execution plan → iterator tree → handler calls
  → [Storage Engine] handler API → buffer pool → disk I/O
  → [Result Set]     rows formatted → sent to client
```

**Lab**:
```sql
-- Enable general log to trace query flow
SHOW VARIABLES LIKE 'general_log%';
SET GLOBAL general_log = 'ON';

-- Run a query (from another session)
SELECT * FROM lab.employees WHERE department = 'Engineering';

-- Basic execution plan
EXPLAIN SELECT * FROM lab.employees WHERE department = 'Engineering';

-- Tree format — shows iterator execution model
EXPLAIN FORMAT=TREE SELECT * FROM lab.employees WHERE department = 'Engineering';

-- JSON format — includes cost estimates
EXPLAIN FORMAT=JSON SELECT * FROM lab.employees WHERE department = 'Engineering'\G

-- EXPLAIN ANALYZE — actually runs the query with timing
EXPLAIN ANALYZE SELECT * FROM lab.employees
  WHERE department = 'Engineering' AND salary > 80000;

-- Full optimizer trace — see every decision the optimizer makes
SET optimizer_trace = 'enabled=on';
SELECT * FROM lab.employees WHERE salary > 80000;
SELECT JSON_PRETTY(TRACE) FROM information_schema.OPTIMIZER_TRACE\G
SET optimizer_trace = 'enabled=off';

-- Parser error example
SELECT * FORM lab.employees; -- syntax error: FORM vs FROM

-- Preprocessor error example
SELECT * FROM lab.nonexistent_table; -- table doesn't exist

SET GLOBAL general_log = 'OFF';
```

```bash
# Read general log inside container
docker exec mysql-lab tail -50 /var/lib/mysql/general.log
```

**Read**:
- *High Performance MySQL* Ch.8 — Query Execution Engine
- [MySQL Optimizer Tracing](https://dev.mysql.com/doc/dev/mysql-server/latest/PAGE_OPT_TRACE.html)
- [EXPLAIN Output Format](https://dev.mysql.com/doc/refman/8.4/en/explain-output.html)
- MySQL source: `sql/sql_parse.cc` (parser), `sql/sql_optimizer.cc` (optimizer)

**Deliverable**: Run a JOIN query with optimizer trace enabled. Annotate the trace output identifying: table order evaluation, access path selection, cost comparison, and final plan chosen.

---

## 1.5 Storage Engine Layer

**Goal**: Understand how MySQL decouples SQL processing from data storage via a pluggable interface.

**Prerequisites**: 1.4 (Query Execution Flow) — understand that the executor calls the storage engine.

**Key Concepts**:
- **Handler API**: abstract C++ interface between MySQL server (SQL layer) and storage engines
  - Defined in `sql/handler.h` — each engine implements this interface
  - Server doesn't know engine internals; it only calls handler methods
- **Key handler operations**:
  - `ha_open()`: open a table
  - `ha_rnd_init()` / `ha_rnd_next()`: full table scan (init → read rows one by one)
  - `ha_index_init()` / `ha_index_read()` / `ha_index_next()`: index scan
  - `ha_write_row()`: insert a row
  - `ha_update_row()`: update a row (old_row, new_row)
  - `ha_delete_row()`: delete a row
  - `ha_external_lock()`: lock/unlock table for statement execution
- **`handlerton`**: registration struct each engine provides at startup — contains function pointers for create/open/close/commit/rollback
- **Engine capabilities**: not all engines support all features
  - Transactions: InnoDB yes, MyISAM no
  - Foreign keys: InnoDB yes, others no
  - Full-text: InnoDB (since 5.6), MyISAM
  - Spatial: InnoDB (since 5.7), MyISAM
- **Available engines**: InnoDB (default), MyISAM, MEMORY (temp data, hash index), CSV, Archive, Blackhole (replication filter), NDB (MySQL Cluster)
- **Per-table engine**: each table can use a different engine via `ENGINE=xxx` in CREATE TABLE

**Lab**:
```sql
-- Available engines and features
SHOW ENGINES;

-- Which engine each table uses
SELECT TABLE_NAME, ENGINE, ROW_FORMAT, TABLE_ROWS, DATA_LENGTH, INDEX_LENGTH
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = 'lab';

-- Detailed table status
SHOW TABLE STATUS FROM lab\G

-- Handler call counters (how the server calls the engine)
SHOW STATUS LIKE 'Handler%';

-- Run a query, then check handler counters again
FLUSH STATUS;
SELECT * FROM lab.employees WHERE department = 'Engineering';
SHOW STATUS LIKE 'Handler%';
-- Handler_read_key: index lookups, Handler_read_next: sequential reads after index

-- Create a MEMORY table for comparison
CREATE TABLE lab.temp_test (id INT, val VARCHAR(50)) ENGINE=MEMORY;
INSERT INTO lab.temp_test VALUES (1, 'hello'), (2, 'world');
SHOW TABLE STATUS FROM lab WHERE Name = 'temp_test'\G
SELECT * FROM lab.temp_test;
DROP TABLE lab.temp_test;

-- Create a Blackhole table (accepts writes, discards data)
CREATE TABLE lab.blackhole_test (id INT) ENGINE=BLACKHOLE;
INSERT INTO lab.blackhole_test VALUES (1);
SELECT * FROM lab.blackhole_test; -- always empty
DROP TABLE lab.blackhole_test;
```

```bash
# Storage files on disk — InnoDB file-per-table
docker exec mysql-lab ls -lh /var/lib/mysql/lab/
```

**Read**:
- [MySQL Storage Engines](https://dev.mysql.com/doc/refman/8.4/en/storage-engines.html)
- [MEMORY Engine](https://dev.mysql.com/doc/refman/8.4/en/memory-storage-engine.html)
- Source: `sql/handler.h` — Handler API interface definition
- Source: `storage/innobase/handler/ha_innodb.cc` — InnoDB's handler implementation

**Deliverable**: Use `FLUSH STATUS` + `SHOW STATUS LIKE 'Handler%'` before/after 3 different queries (full scan, index lookup, INSERT). Explain which handler methods were called and why.

---

## 1.6 InnoDB vs MyISAM

**Goal**: Understand the fundamental design trade-offs between the two engines and why InnoDB became the default.

**Prerequisites**: 1.5 (Storage Engine Layer) — understand the pluggable architecture.

**Key Concepts**:

| | InnoDB | MyISAM |
|---|---|---|
| **Transactions** | ACID compliant (redo + undo logs) | No transaction support |
| **Locking** | Row-level (record, gap, next-key) | Table-level only |
| **Crash recovery** | Automatic via redo log + doublewrite | Manual `REPAIR TABLE` required |
| **Foreign keys** | Yes (referential integrity enforced) | No |
| **Full-text index** | Yes (since 5.6) | Yes (native, faster historically) |
| **Clustered index** | Yes — PK is the data (B+ Tree leaf = row) | No — heap storage + separate index files |
| **MVCC** | Yes — readers don't block writers | No — reads acquire shared table lock |
| **Storage files** | `.ibd` (tablespace per table) | `.MYD` (data) + `.MYI` (index) |
| **Buffer pool** | Caches data + index pages | Only OS file cache (key buffer for index) |
| **COUNT(*)** | Scans index (no stored count) | Stored metadata (instant) |
| **Compression** | Page-level compression | Row-level with `myisampack` |
| **Default since** | MySQL 5.5 (2010) | Before 5.5 |

- **Why InnoDB won**: crash safety + row-level locking + MVCC → viable for concurrent OLTP workloads. MyISAM's table-level locking became a severe bottleneck under concurrent writes
- **MyISAM niche** (rare today): read-only/read-heavy analytics, `COUNT(*)` heavy workloads, full-text search before InnoDB supported it (pre-5.6)
- **Internal system tables**: MySQL 8.0 converted all system tables to InnoDB (data dictionary). No MyISAM system tables remain

**Lab**:
```sql
-- Compare engine features
SHOW ENGINES;

-- InnoDB-specific status (detailed internal state)
SHOW ENGINE INNODB STATUS\G

-- Table sizes and engine per table
SELECT TABLE_NAME, ENGINE, ROW_FORMAT, TABLE_ROWS,
  ROUND(DATA_LENGTH/1024/1024, 2) AS data_mb,
  ROUND(INDEX_LENGTH/1024/1024, 2) AS index_mb
FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'lab';

-- InnoDB metrics
SELECT NAME, COUNT, STATUS FROM information_schema.INNODB_METRICS
  WHERE STATUS = 'enabled' LIMIT 20;

-- System tables are all InnoDB in 8.0
SELECT ENGINE, COUNT(*) FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = 'mysql' GROUP BY ENGINE;
```

```bash
# InnoDB: one .ibd per table (file-per-table mode)
docker exec mysql-lab ls -lh /var/lib/mysql/lab/

# System tablespace
docker exec mysql-lab ls -lh /var/lib/mysql/ibdata1

# Undo tablespace files (8.0+)
docker exec mysql-lab ls -lh /var/lib/mysql/undo_*
```

**Read**:
- [InnoDB Introduction](https://dev.mysql.com/doc/refman/8.4/en/innodb-introduction.html)
- [MyISAM Storage Engine](https://dev.mysql.com/doc/refman/8.4/en/myisam-storage-engine.html)
- *High Performance MySQL* Ch.1 — Storage Engines comparison
- *High Performance MySQL* Ch.4 — InnoDB overview

**Deliverable**: Explain 3 scenarios where MyISAM might still be considered over InnoDB. For each, explain the specific advantage and why InnoDB may not be suitable. Also explain why these scenarios are increasingly rare.

---

## How It All Fits Together

```
Client connects (TCP 3306)
  → Connection Manager (1.2): handshake, auth, assign thread
  → Thread (1.3): one OS thread per connection
  → SQL text arrives (COM_QUERY)
  → Parser (1.4): SQL → AST
  → Preprocessor (1.4): semantic checks, permissions
  → Optimizer (1.4): cost-based plan selection
  → Executor (1.4): iterator tree, calls Handler API
  → Storage Engine (1.5): InnoDB reads pages from buffer pool / disk
  → Result sent back to client
  → Thread returns to sleep (or thread cache on disconnect)
```

---

## Progress Tracker

| # | Topic | Status |
|---|-------|--------|
| 1.1 | Server Architecture | [ ] |
| 1.2 | Client Protocol & Connection | [ ] |
| 1.3 | Thread Model | [ ] |
| 1.4 | Query Execution Flow | [ ] |
| 1.5 | Storage Engine Layer | [ ] |
| 1.6 | InnoDB vs MyISAM | [ ] |
