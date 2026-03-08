# Phase 3: Query Optimization

Master MySQL's cost-based optimizer, learn to read execution plans, and design effective index strategies.

> Each topic below is **self-contained**. Jump into any item freely — prerequisites are noted where needed.

## First Principle (Nguyên lý 5)

**Chọn kế hoạch thực thi** — Nhiều cách chạy một query; optimizer chọn thế nào?

- **Hỏi trước khi đọc:** Với một JOIN 3 bảng có bao nhiêu thứ tự join? Cost là gì? Làm sao biết plan đang chạy đúng/sai?
- **Ánh xạ:** [first-principles-learning.md](../first-principles-learning.md) → Nguyên lý 5. Topics 3.1–3.4 = cost-based optimizer, execution plan, index strategy, query rewrite.

## Topic Map

```
┌─────────────────────────────────────────────────────┐
│              3.1 Query Optimizer                     │
│    (cost model, join algorithms, optimizer hints)    │
├─────────────────────────────────────────────────────┤
│              3.2 Execution Plan                      │
│    (EXPLAIN, access types, key metrics)              │
├──────────────────────┬──────────────────────────────┤
│ 3.3 Index Strategy   │ 3.4 Query Rewrite            │
│ (composite, covering,│ (subquery → JOIN, semi-join,  │
│  ICP, skip scan)     │  CTE, derived table merging)  │
└──────────────────────┴──────────────────────────────┘
```

---

## 3.1 Query Optimizer

**Goal**: Understand how MySQL chooses the best execution plan for a query.

**Key Concepts**:
- **Cost-based optimizer**: evaluates multiple plans and picks the one with lowest estimated cost
- Cost factors: disk I/O (page reads), CPU (comparisons, sorting), memory, temporary tables
- **Cost model tables** (`mysql.server_cost`, `mysql.engine_cost`): tunable cost constants
- **Join algorithms**:
  - **Nested Loop Join (NLJ)**: default, row-by-row from outer to inner table
  - **Hash Join** (8.0.18+): builds hash table for equi-joins without usable indexes
  - **Batched Key Access (BKA)**: batches key lookups to reduce random I/O, uses MRR
- **Join order optimization**: `n!` possible orders → optimizer uses heuristics + greedy search
- **Optimizer hints**: `/*+ NO_INDEX(...) */`, `/*+ HASH_JOIN(...) */`, `/*+ JOIN_ORDER(...) */`
- **Optimizer switches**: `SET optimizer_switch='index_merge=off,mrr=on'`

**Lab**:
```sql
-- Current cost model
SELECT * FROM mysql.server_cost;
SELECT * FROM mysql.engine_cost;

-- Current optimizer switches
SHOW VARIABLES LIKE 'optimizer_switch'\G

-- Compare NLJ vs Hash Join
EXPLAIN FORMAT=TREE
  SELECT e.name, o.amount
  FROM lab.employees e JOIN lab.orders o ON e.id = o.employee_id
  WHERE e.department = 'Engineering';

-- Force Hash Join (drop useful index first, or use hint)
EXPLAIN FORMAT=TREE
  SELECT /*+ HASH_JOIN(e, o) */ e.name, o.amount
  FROM lab.employees e JOIN lab.orders o ON e.id = o.employee_id;

-- Full optimizer trace
SET optimizer_trace = 'enabled=on';
SELECT * FROM lab.employees WHERE department = 'Engineering' AND salary > 80000;
SELECT JSON_PRETTY(TRACE) FROM information_schema.OPTIMIZER_TRACE\G
SET optimizer_trace = 'enabled=off';

-- Join order: see which table the optimizer reads first
EXPLAIN FORMAT=TREE
  SELECT * FROM lab.employees e
  JOIN lab.orders o ON e.id = o.employee_id
  WHERE o.amount > 500;
```

**Read**:
- [MySQL Query Optimizer](https://dev.mysql.com/doc/refman/8.4/en/query-optimization.html)
- [Optimizer Hints](https://dev.mysql.com/doc/refman/8.4/en/optimizer-hints.html)
- *High Performance MySQL* Ch.8 — The Optimizer

**Deliverable**: Compare NLJ vs Hash Join for a query. Show cost difference using optimizer trace and explain when each is preferred.

---

## 3.2 Execution Plan

**Goal**: Read and interpret `EXPLAIN` output to identify query bottlenecks.

**Prerequisites**: 3.1 (Query Optimizer) — understand what the optimizer produces.

**Key Concepts**:
- **Access type hierarchy** (best → worst): `system` > `const` > `eq_ref` > `ref` > `fulltext` > `ref_or_null` > `range` > `index` > `ALL`
- **EXPLAIN columns**: `type`, `possible_keys`, `key`, `key_len`, `ref`, `rows`, `filtered`, `Extra`
- **EXPLAIN FORMAT=TREE**: shows iterator-based execution plan with nesting
- **EXPLAIN ANALYZE** (8.0.18+): actually executes the query — shows real rows, loops, timing
- **Key Extra values**: `Using index` (covering), `Using where`, `Using temporary`, `Using filesort`, `Using index condition` (ICP)
- **estimated rows vs actual rows**: large gap indicates stale statistics → `ANALYZE TABLE`

**Lab**:
```sql
-- Basic EXPLAIN
EXPLAIN SELECT * FROM lab.employees WHERE department = 'Engineering';

-- Tree format — shows execution iterator tree
EXPLAIN FORMAT=TREE SELECT * FROM lab.employees
  WHERE department = 'Engineering' AND salary > 80000;

-- EXPLAIN ANALYZE — actual execution metrics
EXPLAIN ANALYZE SELECT * FROM lab.employees
  WHERE department = 'Engineering' AND salary > 80000;

-- JSON format — most detailed, includes cost info
EXPLAIN FORMAT=JSON SELECT * FROM lab.employees
  WHERE department = 'Engineering';

-- Spot the difference: actual vs estimated
EXPLAIN ANALYZE
  SELECT e.name, COUNT(o.id) AS order_count
  FROM lab.employees e
  JOIN lab.orders o ON e.id = o.employee_id
  GROUP BY e.name
  ORDER BY order_count DESC;

-- Refresh statistics
ANALYZE TABLE lab.employees;
ANALYZE TABLE lab.orders;
```

**Read**:
- [EXPLAIN Output Format](https://dev.mysql.com/doc/refman/8.4/en/explain-output.html)
- [EXPLAIN ANALYZE](https://dev.mysql.com/doc/refman/8.4/en/explain.html#explain-analyze)
- *High Performance MySQL* Ch.7 — EXPLAIN

**Deliverable**: Take 3 different queries, run `EXPLAIN ANALYZE`, annotate each line of the output explaining what it means. Identify the bottleneck in each.

---

## 3.3 Index Strategy

**Goal**: Design effective indexes that minimize I/O and avoid common indexing pitfalls.

**Prerequisites**: Phase 2.2 (B+ Tree Index) — understand clustered vs secondary indexes.

**Key Concepts**:
- **Composite index**: multi-column index following **leftmost prefix rule** — `(a, b, c)` supports queries on `(a)`, `(a, b)`, `(a, b, c)` but NOT `(b)` or `(c)` alone
- **Covering index**: index contains all columns needed → no bookmark lookup → `Using index` in Extra
- **Index Condition Pushdown (ICP)** (5.6+): filter conditions pushed to storage engine level, reduces rows sent to SQL layer → `Using index condition` in Extra
- **Index Skip Scan** (8.0.13+): allows using composite index even when leftmost prefix is skipped (low-cardinality leading column)
- **Invisible index**: `ALTER INDEX ... INVISIBLE` — optimizer ignores it but still maintained. Safe way to test index removal
- **Index selectivity**: `COUNT(DISTINCT col) / COUNT(*)` — higher is better for B+ Tree indexes
- **Over-indexing**: too many indexes slow down writes (each INSERT/UPDATE must maintain all indexes)

**Lab**:
```sql
-- Current indexes
SHOW INDEX FROM lab.employees;

-- Composite index experiment
CREATE INDEX idx_dept_salary ON lab.employees(department, salary);

-- Leftmost prefix works
EXPLAIN FORMAT=TREE SELECT * FROM lab.employees WHERE department = 'Engineering';
EXPLAIN FORMAT=TREE SELECT * FROM lab.employees WHERE department = 'Engineering' AND salary > 80000;

-- Leftmost prefix violated — index not used
EXPLAIN FORMAT=TREE SELECT * FROM lab.employees WHERE salary > 80000;

-- Covering index — "Using index" in Extra
EXPLAIN SELECT department, salary FROM lab.employees
  WHERE department = 'Engineering' AND salary > 80000;

-- ICP demonstration
EXPLAIN SELECT * FROM lab.employees
  WHERE department = 'Engineering' AND name LIKE 'A%';

-- Invisible index: safe removal test
ALTER TABLE lab.employees ALTER INDEX idx_dept_salary INVISIBLE;
EXPLAIN SELECT * FROM lab.employees WHERE department = 'Engineering' AND salary > 80000;
ALTER TABLE lab.employees ALTER INDEX idx_dept_salary VISIBLE;

-- Index selectivity
SELECT
  COUNT(DISTINCT department) / COUNT(*) AS dept_selectivity,
  COUNT(DISTINCT name) / COUNT(*) AS name_selectivity
FROM lab.employees;

-- Cleanup
DROP INDEX idx_dept_salary ON lab.employees;
```

**Read**:
- [InnoDB Index Types](https://dev.mysql.com/doc/refman/8.4/en/innodb-index-types.html)
- [Index Condition Pushdown](https://dev.mysql.com/doc/refman/8.4/en/index-condition-pushdown-optimization.html)
- *High Performance MySQL* Ch.5 — Indexing for High Performance

**Deliverable**: Design an optimal index strategy for the `orders` table given 5 common query patterns. Justify each index choice with `EXPLAIN ANALYZE` output.

---

## 3.4 Query Rewrite

**Goal**: Understand how the optimizer transforms queries internally and how to write optimizer-friendly SQL.

**Prerequisites**: 3.1 (Optimizer), 3.2 (Execution Plan).

**Key Concepts**:
- **Subquery → JOIN transformation**: optimizer can convert `IN (SELECT ...)` to semi-join
- **Semi-join strategies**: `FirstMatch`, `LooseScan`, `Materialization`, `DuplicateWeedout` — each has different cost characteristics
- **Derived table merging**: optimizer merges simple subqueries in FROM clause into outer query (avoids materialization)
- **CTE optimization**: non-recursive CTEs can be merged or materialized. Use `/*+ MERGE(cte) */` or `/*+ NO_MERGE(cte) */`
- **Anti-patterns**: correlated subquery in SELECT, `OR` across different columns, function on indexed column (`WHERE YEAR(date_col) = 2024`)
- **Sargable predicates**: conditions that can use an index — avoid wrapping indexed columns in functions

**Lab**:
```sql
-- Subquery vs JOIN: optimizer trace shows transformation
SET optimizer_trace = 'enabled=on';

-- This IN-subquery gets transformed to semi-join
SELECT * FROM lab.employees
  WHERE id IN (SELECT employee_id FROM lab.orders WHERE amount > 1000);
SELECT JSON_PRETTY(TRACE) FROM information_schema.OPTIMIZER_TRACE\G

SET optimizer_trace = 'enabled=off';

-- Compare: explicit JOIN vs subquery
EXPLAIN ANALYZE
  SELECT DISTINCT e.* FROM lab.employees e
  JOIN lab.orders o ON e.id = o.employee_id
  WHERE o.amount > 1000;

EXPLAIN ANALYZE
  SELECT * FROM lab.employees
  WHERE id IN (SELECT employee_id FROM lab.orders WHERE amount > 1000);

-- Derived table merging
EXPLAIN FORMAT=TREE
  SELECT * FROM (SELECT * FROM lab.employees WHERE department = 'Engineering') t
  WHERE t.salary > 80000;

-- Anti-pattern: function on indexed column prevents index usage
EXPLAIN SELECT * FROM lab.orders WHERE YEAR(order_date) = 2024;

-- Sargable rewrite
EXPLAIN SELECT * FROM lab.orders
  WHERE order_date >= '2024-01-01' AND order_date < '2025-01-01';

-- CTE materialization control
EXPLAIN FORMAT=TREE
  WITH eng AS (SELECT * FROM lab.employees WHERE department = 'Engineering')
  SELECT * FROM eng WHERE salary > 80000;
```

**Read**:
- [Optimizing Subqueries with Semi-Join](https://dev.mysql.com/doc/refman/8.4/en/semijoins.html)
- [Derived Table Optimization](https://dev.mysql.com/doc/refman/8.4/en/derived-table-optimization.html)
- *High Performance MySQL* Ch.8 — Query Rewriting

**Deliverable**: Take 3 slow queries using subqueries, rewrite them as JOINs. Compare `EXPLAIN ANALYZE` before and after. Show the optimizer trace transformation.

---

## Progress Tracker

| # | Topic | Status |
|---|-------|--------|
| 3.1 | Query Optimizer | [ ] |
| 3.2 | Execution Plan | [ ] |
| 3.3 | Index Strategy | [ ] |
| 3.4 | Query Rewrite | [ ] |
