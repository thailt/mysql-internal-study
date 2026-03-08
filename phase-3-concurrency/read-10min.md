# Phase 3: Query Optimization — 10 phút

## Mục tiêu
Làm chủ cost-based optimizer, đọc execution plan và thiết kế index. Các topic self-contained.

---

## 3.1 Query Optimizer
- **Cost-based optimizer**: đánh giá nhiều plan, chọn cost thấp (disk I/O, CPU, memory, temp). **Cost model**: `mysql.server_cost`, `mysql.engine_cost` — hằng số cost có thể tune.
- **Join algorithms**: **NLJ** (mặc định, row-by-row); **Hash Join** (8.0.18+, equi-join khi không có index phù hợp); **BKA** (batch key, dùng MRR). **Join order**: n! → heuristics + greedy search.
- **Optimizer hints**: `/*+ NO_INDEX(t i) */`, `/*+ HASH_JOIN(t1 t2) */`, `/*+ JOIN_ORDER(t1, t2) */`. **optimizer_switch**: index_merge, mrr, batched_key_access, v.v.

**Lab**: server_cost, engine_cost; optimizer_switch; EXPLAIN FORMAT=TREE cho JOIN (NLJ vs HASH_JOIN); optimizer_trace cho một query; EXPLAIN xem join order (bảng nào đọc trước).

---

## 3.2 Execution Plan
- **Access type** (tốt → kém): system > const > eq_ref > ref > fulltext > ref_or_null > range > index > ALL. Cột quan trọng: type, possible_keys, key, key_len, ref, rows, filtered, Extra.
- **EXPLAIN FORMAT=TREE**: kế hoạch dạng iterator. **EXPLAIN ANALYZE**: chạy query, hiện actual rows, loops, time. **Extra**: Using index (covering), Using where, Using temporary, Using filesort, Using index condition (ICP).
- **rows**: ước lượng; nếu khác nhiều so với actual → thống kê cũ → `ANALYZE TABLE`.

**Lab**: EXPLAIN thường, FORMAT=TREE, FORMAT=JSON, ANALYZE; so sánh estimated vs actual trong ANALYZE; ANALYZE TABLE lab.employees, lab.orders.

---

## 3.3 Index Strategy
- **Composite index**: **leftmost prefix** — (a,b,c) dùng cho (a), (a,b), (a,b,c); không cho (b), (c) đơn. **Covering index**: mọi cột cần có trong index → Extra "Using index". **ICP** (5.6+): điều kiện WHERE đẩy xuống engine → "Using index condition". **Index Skip Scan** (8.0.13+): dùng composite khi bỏ cột đầu (leading column cardinality thấp).
- **Invisible index**: ALTER INDEX ... INVISIBLE — optimizer bỏ qua, index vẫn được maintain; thử trước khi DROP. **Selectivity**: COUNT(DISTINCT col)/COUNT(*); cao hơn tốt cho B+ Tree. **Over-indexing**: nhiều index → INSERT/UPDATE chậm (phải cập nhật hết).

**Lab**: SHOW INDEX; tạo idx (department, salary); EXPLAIN WHERE department; WHERE department AND salary; WHERE salary (không dùng leftmost); covering (chỉ department, salary); ICP (department + name LIKE); INVISIBLE rồi EXPLAIN; tính selectivity department vs name; DROP index thử nghiệm.

---

## 3.4 Query Rewrite
- **Subquery → semi-join**: IN (SELECT ...) có thể được chuyển thành semi-join (FirstMatch, LooseScan, Materialization, DuplicateWeedout); xem trong optimizer trace. **Derived table merging**: subquery trong FROM đơn giản có thể merge vào outer.
- **CTE**: non-recursive có thể merge hoặc materialize; hint MERGE(cte) / NO_MERGE(cte). **Anti-pattern**: correlated subquery trong SELECT; OR nhiều cột; function trên cột index (YEAR(date_col)=2024). **Sargable**: điều kiện để dùng index — tránh bọc cột trong function; dùng range cho date.

**Lab**: optimizer_trace cho query IN (SELECT employee_id FROM orders WHERE amount>1000); so sánh EXPLAIN ANALYZE JOIN vs IN-subquery; derived table merge (SELECT * FROM (SELECT * FROM employees WHERE department=...) t WHERE salary>...); EXPLAIN WHERE YEAR(order_date)=2024 vs WHERE order_date >= '2024-01-01' AND order_date < '2025-01-01'; CTE với MERGE/NO_MERGE.

---

## Tóm tắt
Cost-based optimizer → EXPLAIN/ANALYZE (type, rows, Extra) → Index: composite leftmost, covering, ICP, invisible để thử → Query: sargable, tránh function trên cột index, ưu tiên JOIN/range thay subquery.
