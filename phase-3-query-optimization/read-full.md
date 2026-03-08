# Phase 3: Query Optimization — Full content

Master MySQL's cost-based optimizer, learn to read execution plans, and design effective index strategies.

> Each topic below is **self-contained**. Jump into any item freely — prerequisites are noted where needed.

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

**Goal**: Understand how MySQL chooses the best execution plan.

**Key Concepts**: Cost-based optimizer; cost model (server_cost, engine_cost); Join: NLJ, Hash Join (8.0.18+), BKA; join order; optimizer hints and optimizer_switch.

**Lab**: mysql.server_cost, engine_cost; optimizer_switch; EXPLAIN FORMAT=TREE NLJ vs HASH_JOIN; optimizer_trace; join order in EXPLAIN.

**Read**: MySQL Query Optimizer, Optimizer Hints, *High Performance MySQL* Ch.8.

**Deliverable**: Compare NLJ vs Hash Join with optimizer trace; explain when each is preferred.

---

## 3.2 Execution Plan

**Goal**: Read and interpret EXPLAIN to find bottlenecks.

**Key Concepts**: Access type (system → ALL); EXPLAIN columns; FORMAT=TREE, ANALYZE; Extra (Using index, temporary, filesort, index condition); estimated vs actual rows → ANALYZE TABLE.

**Lab**: EXPLAIN, FORMAT=TREE, FORMAT=JSON, ANALYZE; compare estimated/actual; ANALYZE TABLE.

**Read**: EXPLAIN Output Format, EXPLAIN ANALYZE, *High Performance MySQL* Ch.7.

**Deliverable**: Annotate EXPLAIN ANALYZE for 3 queries; identify bottleneck in each.

---

## 3.3 Index Strategy

**Goal**: Design indexes that minimize I/O and avoid pitfalls.

**Key Concepts**: Composite (leftmost prefix); covering index; ICP; skip scan (8.0.13+); invisible index; selectivity; over-indexing.

**Lab**: SHOW INDEX; create composite; leftmost experiments; covering; ICP; INVISIBLE; selectivity; DROP.

**Read**: InnoDB Index Types, Index Condition Pushdown, *High Performance MySQL* Ch.5.

**Deliverable**: Optimal index strategy for `orders` given 5 query patterns; justify with EXPLAIN ANALYZE.

---

## 3.4 Query Rewrite

**Goal**: How optimizer rewrites queries and how to write optimizer-friendly SQL.

**Key Concepts**: Subquery → semi-join; derived table merging; CTE merge/materialize; anti-patterns (correlated subquery, OR, function on indexed column); sargable predicates.

**Lab**: optimizer_trace for IN-subquery; JOIN vs subquery EXPLAIN ANALYZE; derived merge; YEAR() vs range; CTE hints.

**Read**: Semi-Join, Derived Table Optimization, *High Performance MySQL* Ch.8.

**Deliverable**: Rewrite 3 slow subquery queries as JOINs; compare EXPLAIN ANALYZE and show optimizer trace.

---

## Progress Tracker

| # | Topic | Status |
|---|-------|--------|
| 3.1 | Query Optimizer | [ ] |
| 3.2 | Execution Plan | [ ] |
| 3.3 | Index Strategy | [ ] |
| 3.4 | Query Rewrite | [ ] |
