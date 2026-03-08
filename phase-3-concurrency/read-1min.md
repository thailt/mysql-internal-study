# Phase 3: Query Optimization — 1 phút

**Mục tiêu**: Làm chủ cost-based optimizer, đọc execution plan và thiết kế index hiệu quả.

- **Optimizer (3.1)**: Cost-based; cost model (server_cost, engine_cost); NLJ, Hash Join, BKA; join order; hints và optimizer_switch.
- **Execution Plan (3.2)**: EXPLAIN type (system → ALL), possible_keys, key, rows, filtered, Extra; FORMAT=TREE, ANALYZE; Using index, Using temporary, Using filesort.
- **Index Strategy (3.3)**: Composite (leftmost prefix), covering index, ICP, skip scan; invisible index; selectivity; tránh over-indexing.
- **Query Rewrite (3.4)**: Subquery → semi-join; derived table merging; CTE merge/materialize; tránh function trên cột index (sargable).

**Topic**: 3.1 Query Optimizer → 3.2 Execution Plan → 3.3 Index Strategy → 3.4 Query Rewrite.
