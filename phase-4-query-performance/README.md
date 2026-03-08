# Phase 4: The Search Problem — Query Performance (Week 8–9)

> *Finding specific data among millions of rows must be fast. How does MySQL choose the best path?*

Every query is a search problem. A table with 10 million rows stored across thousands of 16KB pages — how do you find the one row you need without reading them all? This phase builds from that constraint to derive the optimizer, execution plans, index strategies, and query patterns that make MySQL fast.

## First Principle (Nguyên lý 5)

**Chọn kế hoạch thực thi** — Tìm 1 row trong triệu row phải nhanh; full scan O(n) không chấp nhận được.

- **Hỏi trước khi đọc:** Optimizer đánh giá cost thế nào? EXPLAIN vs EXPLAIN ANALYZE dùng khi nào? Index strategy (composite, covering, ICP) giải quyết bài toán gì?
- **Ánh xạ:** [first-principles-learning.md](../first-principles-learning.md) → Nguyên lý 5. Phase 4 đi sâu hơn vào constraint "search" + optimizer + index.

## Why This Phase Now?

Phase 2 explained *how* data is stored (B+ Trees, pages, buffer pool). Phase 3 explained *how* concurrent access works (locks, MVCC, isolation). Now the question becomes: given all that machinery, **how does MySQL find data efficiently?** The answer is the optimizer + indexes — and understanding both requires knowing the storage layer first.

## Constraint Chain

```
Need to find 1 row among millions
  → Full table scan = O(n) = too slow
  → Index = O(log n) but many possible indexes
    → Which index? Which join order? → Cost-based optimizer
      → Can't optimize blind → need EXPLAIN ANALYZE
  → Right index design = 1000x faster
    → Composite index (leftmost prefix), covering index, ICP
  → Optimizer can't fix bad SQL → sargable predicates, anti-patterns
```

## Topic Map

```
┌─────────────────────────────────────────────────────────┐
│                4.1 How the Optimizer Thinks              │
│      (cost model, join algorithms, join order,           │
│       optimizer hints, optimizer trace)                   │
├─────────────────────────────────────────────────────────┤
│                4.2 Reading Execution Plans                │
│      (EXPLAIN, access types, FORMAT=TREE/JSON,           │
│       EXPLAIN ANALYZE, estimated vs actual)               │
├────────────────────────┬────────────────────────────────┤
│ 4.3 Index Strategy     │ 4.4 Query Rewrite              │
│ (composite, covering,  │ (subquery → JOIN, semi-join,   │
│  ICP, skip scan,       │  derived table merging, CTE,   │
│  invisible index)      │  sargable predicates)          │
└────────────────────────┴────────────────────────────────┘
```

---

## 4.1 How the Optimizer Thinks

**Goal**: Understand how MySQL evaluates hundreds of possible plans and picks the cheapest one.

**Why?** A query joining 3 tables has `3! = 6` possible join orders. Each order can use different access paths (full scan, index range, index lookup). That's potentially hundreds of combinations. Picking the wrong one means seconds instead of milliseconds — the optimizer exists to solve this combinatorial problem.

**Key Concepts**:
- **Cost-based optimizer**: evaluates candidate plans by estimated cost, picks the lowest
- **Cost factors**: disk I/O (page reads from buffer pool or disk), CPU (row comparisons, sorting), memory consumption, temporary tables
- **Cost model tables**: `mysql.server_cost` (CPU operations) and `mysql.engine_cost` (I/O operations) — tunable constants that control how the optimizer prices each operation
- **Join algorithms**:
  - **Nested Loop Join (NLJ)**: default. For each row in outer table, scan inner table. Works well when inner table has an index
  - **Hash Join** (8.0.18+): builds in-memory hash table from smaller table, probes with larger. Used for equi-joins without usable index
  - **Batched Key Access (BKA)**: batches key lookups from NLJ into sorted order, uses **Multi-Range Read (MRR)** to reduce random I/O
- **Join order**: `n!` possible orderings → optimizer uses **greedy search** with heuristics to prune search space
- **Optimizer hints**: inline directives like `/*+ HASH_JOIN(t1, t2) */`, `/*+ JOIN_ORDER(t1, t2) */`, `/*+ NO_INDEX(t1 idx_col) */`
- **Optimizer switches**: session/global variable `optimizer_switch` — toggles for features like `index_merge`, `mrr`, `batched_key_access`, `hash_join`

**Lab**:
```sql
-- Inspect cost model tables
SELECT * FROM mysql.server_cost;
SELECT * FROM mysql.engine_cost;

-- Current optimizer switches
SHOW VARIABLES LIKE 'optimizer_switch'\G

-- NLJ with index: optimizer picks nested loop because index exists
EXPLAIN FORMAT=TREE
  SELECT e.name, o.amount
  FROM lab.employees e
  JOIN lab.orders o ON e.id = o.employee_id
  WHERE e.department = 'Engineering';

-- Force Hash Join with hint
EXPLAIN FORMAT=TREE
  SELECT /*+ HASH_JOIN(e, o) */ e.name, o.amount
  FROM lab.employees e
  JOIN lab.orders o ON e.id = o.employee_id;

-- Optimizer trace: see cost comparison and join order selection
SET optimizer_trace = 'enabled=on';
SELECT e.name, o.amount
  FROM lab.employees e
  JOIN lab.orders o ON e.id = o.employee_id
  WHERE e.department = 'Engineering' AND o.amount > 500;
SELECT JSON_PRETTY(TRACE) FROM information_schema.OPTIMIZER_TRACE\G
SET optimizer_trace = 'enabled=off';

-- Join order: which table does the optimizer read first?
EXPLAIN FORMAT=TREE
  SELECT * FROM lab.employees e
  JOIN lab.orders o ON e.id = o.employee_id
  WHERE o.amount > 500;
```

**Read**:
- [MySQL Query Optimizer](https://dev.mysql.com/doc/refman/8.4/en/query-optimization.html)
- [Optimizer Cost Model](https://dev.mysql.com/doc/refman/8.4/en/cost-model.html)
- [Optimizer Hints](https://dev.mysql.com/doc/refman/8.4/en/optimizer-hints.html)
- *High Performance MySQL* Ch.8 — The Optimizer

**Deliverable**: Compare NLJ vs Hash Join for the same query. Show the cost difference via optimizer trace. Explain when each algorithm wins.

---

## 4.2 Reading Execution Plans

**Goal**: Read and interpret `EXPLAIN` output to diagnose query performance.

**Why?** You can't optimize what you can't measure. `EXPLAIN` is the X-ray of query performance — it shows exactly which plan the optimizer chose, which indexes it uses, how many rows it expects to touch, and where the bottlenecks are. Without this skill, optimization is guesswork.

**Prerequisites**: 4.1 (How the Optimizer Thinks) — you need to understand what the optimizer produces before reading its output.

**Key Concepts**:
- **Access type hierarchy** (best → worst): `system` > `const` > `eq_ref` > `ref` > `fulltext` > `ref_or_null` > `range` > `index` > `ALL`
- **EXPLAIN columns**: `type` (access type), `possible_keys`, `key` (chosen index), `key_len` (bytes used from index), `rows` (estimated rows to examine), `filtered` (% rows surviving WHERE), `Extra` (additional info)
- **EXPLAIN FORMAT=TREE**: iterator-based execution plan showing nesting and data flow
- **EXPLAIN FORMAT=JSON**: most detailed — includes cost estimates per step
- **EXPLAIN ANALYZE** (8.0.18+): actually runs the query — reports real row counts, loop counts, and wall-clock timing per iterator
- **Key Extra values**:
  - `Using index`: **covering index** — all data read from index, no table access
  - `Using where`: rows filtered at SQL layer after storage engine returns them
  - `Using temporary`: intermediate results stored in temp table (GROUP BY, DISTINCT)
  - `Using filesort`: extra sort pass needed (ORDER BY without matching index)
  - `Using index condition`: **Index Condition Pushdown (ICP)** — filter pushed to engine
- **Estimated vs actual rows**: a large gap signals stale statistics → fix with `ANALYZE TABLE`

**Lab**:
```sql
-- Basic EXPLAIN: see access type, key, rows, Extra
EXPLAIN SELECT * FROM lab.employees WHERE department = 'Engineering';

-- Tree format: iterator model with nesting
EXPLAIN FORMAT=TREE
  SELECT * FROM lab.employees
  WHERE department = 'Engineering' AND salary > 80000;

-- EXPLAIN ANALYZE: actual execution with timing
EXPLAIN ANALYZE
  SELECT * FROM lab.employees
  WHERE department = 'Engineering' AND salary > 80000;

-- JSON format: full cost breakdown
EXPLAIN FORMAT=JSON
  SELECT * FROM lab.employees WHERE department = 'Engineering'\G

-- Estimated vs actual: spot the gap
EXPLAIN ANALYZE
  SELECT e.name, COUNT(o.id) AS order_count
  FROM lab.employees e
  JOIN lab.orders o ON e.id = o.employee_id
  GROUP BY e.name
  ORDER BY order_count DESC;

-- Fix stale statistics
ANALYZE TABLE lab.employees;
ANALYZE TABLE lab.orders;
```

**Read**:
- [EXPLAIN Output Format](https://dev.mysql.com/doc/refman/8.4/en/explain-output.html)
- [EXPLAIN ANALYZE](https://dev.mysql.com/doc/refman/8.4/en/explain.html#explain-analyze)
- *High Performance MySQL* Ch.7 — EXPLAIN

**Deliverable**: Take 3 different queries, run `EXPLAIN ANALYZE` on each. Annotate every line of the output. Identify the bottleneck in each query.

---

## 4.3 Index Strategy

**Goal**: Design indexes that turn full table scans into sub-millisecond lookups.

**Why?** The right index turns a 10-second full scan into a 1ms lookup — that's a 10,000x improvement from a single DDL statement. Index design is the highest-ROI optimization skill. But indexes aren't free: each one costs write throughput and storage. The art is choosing the minimal set that covers your critical queries.

**Prerequisites**: Phase 2.2 (B+ Tree Index) — understand clustered vs secondary index structure.

**Key Concepts**:
- **Composite index** follows the **leftmost prefix rule**: index `(a, b, c)` supports queries on `(a)`, `(a, b)`, `(a, b, c)` — but NOT `(b)` or `(c)` alone
- **Covering index**: index contains all columns the query needs → no bookmark lookup to clustered index → `Using index` in Extra
- **Index Condition Pushdown (ICP)** (5.6+): conditions on indexed columns that aren't part of the lookup key are pushed to the storage engine for filtering → `Using index condition` in Extra. Reduces rows sent to SQL layer
- **Index Skip Scan** (8.0.13+): allows using a composite index even when the leftmost prefix is missing — if the leading column has low cardinality, the optimizer "skips" through its distinct values
- **Invisible index**: `ALTER TABLE ... ALTER INDEX idx INVISIBLE` — optimizer ignores it but it's still maintained. Safe way to test the impact of dropping an index without actually dropping it
- **Selectivity**: `COUNT(DISTINCT col) / COUNT(*)` — higher selectivity = more effective index. A column with 2 distinct values among 1M rows has terrible selectivity
- **Over-indexing**: every INSERT/UPDATE/DELETE must maintain all indexes. Too many indexes = slow writes, wasted storage, longer backup times

**Lab**:
```sql
-- Current indexes
SHOW INDEX FROM lab.employees;
SHOW INDEX FROM lab.orders;

-- Create composite index
CREATE INDEX idx_dept_salary ON lab.employees(department, salary);

-- Leftmost prefix: works
EXPLAIN FORMAT=TREE SELECT * FROM lab.employees WHERE department = 'Engineering';
EXPLAIN FORMAT=TREE SELECT * FROM lab.employees WHERE department = 'Engineering' AND salary > 80000;

-- Leftmost prefix: violated — index NOT used
EXPLAIN FORMAT=TREE SELECT * FROM lab.employees WHERE salary > 80000;

-- Covering index: "Using index" — no table access
EXPLAIN SELECT department, salary FROM lab.employees
  WHERE department = 'Engineering' AND salary > 80000;

-- ICP: "Using index condition"
EXPLAIN SELECT * FROM lab.employees
  WHERE department = 'Engineering' AND name LIKE 'A%';

-- Invisible index: test impact of removal
ALTER TABLE lab.employees ALTER INDEX idx_dept_salary INVISIBLE;
EXPLAIN FORMAT=TREE SELECT * FROM lab.employees
  WHERE department = 'Engineering' AND salary > 80000;
ALTER TABLE lab.employees ALTER INDEX idx_dept_salary VISIBLE;

-- Selectivity: which column makes a better leading index column?
SELECT
  COUNT(DISTINCT department) / COUNT(*) AS dept_selectivity,
  COUNT(DISTINCT name) / COUNT(*) AS name_selectivity,
  COUNT(DISTINCT salary) / COUNT(*) AS salary_selectivity
FROM lab.employees;

-- Cleanup
DROP INDEX idx_dept_salary ON lab.employees;
```

**Read**:
- [InnoDB Index Types](https://dev.mysql.com/doc/refman/8.4/en/innodb-index-types.html)
- [Index Condition Pushdown](https://dev.mysql.com/doc/refman/8.4/en/index-condition-pushdown-optimization.html)
- [Index Skip Scan](https://dev.mysql.com/doc/refman/8.4/en/range-optimization.html#range-access-skip-scan)
- *High Performance MySQL* Ch.5 — Indexing for High Performance

**Deliverable**: Design an index strategy for the `orders` table given 5 common query patterns. Justify each index with `EXPLAIN ANALYZE` output. Show the before/after difference.

---

## 4.4 Query Rewrite & Anti-Patterns

**Goal**: Write optimizer-friendly SQL and recognize patterns that defeat indexing.

**Why?** The optimizer is smart but it can't fix fundamentally bad SQL. A function wrapping an indexed column silently disables the index. A correlated subquery that runs once per row turns O(n) into O(n²). Understanding these anti-patterns prevents 80% of real-world performance issues — no amount of indexing can compensate for non-sargable queries.

**Prerequisites**: 4.1 (Optimizer), 4.2 (Execution Plans), 4.3 (Index Strategy).

**Key Concepts**:
- **Subquery → semi-join transformation**: the optimizer rewrites `IN (SELECT ...)` into an efficient join using one of four strategies:
  - **FirstMatch**: stop scanning inner table after first match per outer row
  - **LooseScan**: scan inner index, skip duplicates
  - **Materialization**: materialize subquery into temp table, then join
  - **DuplicateWeedout**: use temp table to eliminate duplicate rows
- **Derived table merging**: simple subqueries in FROM clause are merged into the outer query — avoids materialization overhead
- **CTE optimization**: non-recursive CTEs are merged by default. Control with `/*+ MERGE(cte_name) */` or `/*+ NO_MERGE(cte_name) */` hints
- **Anti-patterns that break indexing**:
  - Function on indexed column: `WHERE YEAR(order_date) = 2024` → can't use index on `order_date`
  - `OR` across different columns: `WHERE dept = 'Eng' OR salary > 100000` → often forces full scan
  - Correlated subquery in SELECT: runs subquery once per row in outer table
  - Implicit type conversion: `WHERE varchar_col = 12345` → MySQL casts every row, can't use index
- **Sargable predicates**: conditions that **can** use an index. Rewrite non-sargable to sargable:
  - `YEAR(date) = 2024` → `date >= '2024-01-01' AND date < '2025-01-01'`
  - `amount / 100 > 5` → `amount > 500`

**Lab**:
```sql
-- Subquery vs JOIN: optimizer trace shows semi-join transformation
SET optimizer_trace = 'enabled=on';
SELECT * FROM lab.employees
  WHERE id IN (SELECT employee_id FROM lab.orders WHERE amount > 1000);
SELECT JSON_PRETTY(TRACE) FROM information_schema.OPTIMIZER_TRACE\G
SET optimizer_trace = 'enabled=off';

-- Compare: explicit JOIN vs subquery — often same plan after transformation
EXPLAIN ANALYZE
  SELECT DISTINCT e.* FROM lab.employees e
  JOIN lab.orders o ON e.id = o.employee_id
  WHERE o.amount > 1000;

EXPLAIN ANALYZE
  SELECT * FROM lab.employees
  WHERE id IN (SELECT employee_id FROM lab.orders WHERE amount > 1000);

-- Derived table merging: subquery in FROM is merged
EXPLAIN FORMAT=TREE
  SELECT * FROM (SELECT * FROM lab.employees WHERE department = 'Engineering') t
  WHERE t.salary > 80000;

-- Anti-pattern: function on indexed column prevents index usage
EXPLAIN SELECT * FROM lab.orders WHERE YEAR(order_date) = 2024;

-- Sargable rewrite: now the index can be used
EXPLAIN SELECT * FROM lab.orders
  WHERE order_date >= '2024-01-01' AND order_date < '2025-01-01';

-- CTE materialization control
EXPLAIN FORMAT=TREE
  WITH eng AS (SELECT * FROM lab.employees WHERE department = 'Engineering')
  SELECT * FROM eng WHERE salary > 80000;

EXPLAIN FORMAT=TREE
  WITH eng AS (SELECT /*+ NO_MERGE() */ * FROM lab.employees WHERE department = 'Engineering')
  SELECT * FROM eng WHERE salary > 80000;
```

**Read**:
- [Optimizing Subqueries with Semi-Join](https://dev.mysql.com/doc/refman/8.4/en/semijoins.html)
- [Derived Table Optimization](https://dev.mysql.com/doc/refman/8.4/en/derived-table-optimization.html)
- [Function Call Optimization](https://dev.mysql.com/doc/refman/8.4/en/function-optimization.html)
- *High Performance MySQL* Ch.8 — Query Rewriting

**Deliverable**: Take 3 slow queries using subqueries or anti-patterns. Rewrite each. Compare `EXPLAIN ANALYZE` before and after. Show the optimizer trace transformation for at least one.

---

## How It All Fits Together

```
Query arrives: SELECT * FROM orders WHERE customer_id = 42 AND status = 'shipped'
  → Optimizer (4.1): evaluates candidate plans
      - Full scan: cost = 10,000 page reads
      - Index on customer_id: cost = 5 page reads + bookmark lookups
      - Composite index (customer_id, status): cost = 3 page reads, covering
      → Picks cheapest plan
  → Execution Plan (4.2): EXPLAIN ANALYZE shows the chosen path
      - type=ref, key=idx_cust_status, rows=3, Using index
  → Index Strategy (4.3): composite index exists because we designed it
      - Leftmost prefix matches (customer_id, status)
      - Covering index avoids bookmark lookup
  → Query Rewrite (4.4): query is already sargable
      - No functions on indexed columns
      - No implicit type conversions
  → Result: 3 rows in 0.1ms instead of 10s full scan
```

The optimizer chooses the plan. EXPLAIN reveals the plan. Index strategy ensures good plans exist. Query rewrite ensures the optimizer can actually use them. All four work together — skip any one and performance breaks down.

**What's next?** Phase 5 zooms out to the system level: *what happens when one server isn't enough?* Replication, high availability, backup, partitioning, and production monitoring — scaling MySQL beyond a single instance.

---

## Progress Tracker

| # | Topic | Status |
|---|-------|--------|
| 4.1 | How the Optimizer Thinks | [ ] |
| 4.2 | Reading Execution Plans | [ ] |
| 4.3 | Index Strategy | [ ] |
| 4.4 | Query Rewrite & Anti-Patterns | [ ] |
