# Phase 3: Query Optimization — 5 phút

## Mục tiêu
Làm chủ cost-based optimizer, đọc execution plan và thiết kế index. Các topic self-contained.

---

## 3.1 Query Optimizer
- **Cost-based**: đánh giá nhiều plan, chọn cost thấp nhất (I/O, CPU, temp table). **Cost model**: `mysql.server_cost`, `mysql.engine_cost` có thể chỉnh.
- **Join**: Nested Loop Join (mặc định), Hash Join (8.0.18+, equi-join không index), BKA (batch key, MRR). **Join order**: n! khả năng → heuristics + greedy.
- **Hints**: `/*+ NO_INDEX(...) */`, `/*+ HASH_JOIN(...) */`, `/*+ JOIN_ORDER(...) */`. **optimizer_switch**: bật/tắt index_merge, mrr, v.v.

**Lab nhanh**: `SELECT * FROM mysql.server_cost|engine_cost`; `SHOW VARIABLES LIKE 'optimizer_switch'`; EXPLAIN FORMAT=TREE so sánh NLJ vs HASH_JOIN; `optimizer_trace` + OPTIMIZER_TRACE.

---

## 3.2 Execution Plan
- **Access type** (tốt → kém): system > const > eq_ref > ref > range > index > ALL. Cột: type, possible_keys, key, key_len, ref, rows, filtered, Extra.
- **EXPLAIN FORMAT=TREE**: iterator tree. **EXPLAIN ANALYZE**: chạy thật, hiện rows/loops/timing. **Extra**: Using index (covering), Using where, Using temporary, Using filesort, Using index condition (ICP).
- **rows ước lượng vs thực tế** lệch nhiều → `ANALYZE TABLE` cập nhật thống kê.

**Lab nhanh**: EXPLAIN / FORMAT=TREE / FORMAT=JSON / ANALYZE; so sánh estimated vs actual; ANALYZE TABLE.

---

## 3.3 Index Strategy
- **Composite index**: quy tắc leftmost prefix — (a,b,c) hỗ trợ (a), (a,b), (a,b,c); không hỗ trợ (b), (c) đơn lẻ.
- **Covering index**: đủ cột cần → Extra "Using index", không bookmark lookup. **ICP**: đẩy điều kiện WHERE xuống engine → "Using index condition". **Skip Scan** (8.0.13+): dùng composite khi bỏ qua cột đầu (cardinality thấp).
- **Invisible index**: ALTER INDEX ... INVISIBLE — optimizer bỏ qua, vẫn maintain; dùng thử trước khi DROP. **Selectivity**: COUNT(DISTINCT col)/COUNT(*). Tránh quá nhiều index (chậm ghi).

**Lab nhanh**: Tạo (department, salary); thử leftmost vs không; covering; ICP; INVISIBLE; tính selectivity.

---

## 3.4 Query Rewrite
- **Subquery → semi-join**: IN (SELECT ...) có thể thành semi-join (FirstMatch, LooseScan, Materialization, DuplicateWeedout). **Derived table**: subquery trong FROM có thể merge vào outer.
- **CTE**: MERGE hoặc materialize; hint `/*+ MERGE(cte) */` / `NO_MERGE(cte)`. **Anti-pattern**: correlated subquery trong SELECT; OR nhiều cột; function trên cột index (`YEAR(date_col)=2024`). **Sargable**: điều kiện dùng được index — nên `date_col >= '2024-01-01' AND date_col < '2025-01-01'`.

**Lab nhanh**: optimizer_trace cho IN (subquery); so sánh JOIN vs subquery bằng EXPLAIN ANALYZE; derived merge; so sánh YEAR() vs range trên date.

---

## Tóm tắt
Optimizer chọn plan theo cost → EXPLAIN/ANALYZE đọc type, rows, Extra → Index: composite (leftmost), covering, ICP → Viết query sargable, tránh subquery/function trên cột index.
