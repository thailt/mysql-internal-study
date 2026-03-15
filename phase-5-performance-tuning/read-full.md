# Phase 5 — Performance Tuning (Full)

## 1. Why performance tuning is its own phase

By the time you reach this phase, you already know:
- how data is stored
- how concurrency works
- how durability works
- how the optimizer chooses plans

But real production work asks a different question:

> something is slow — what exactly is wrong, and what is the safest useful intervention?

This is the tuning problem.

It is not enough to know one mechanism in isolation.
You have to integrate:
- query plan understanding
- wait behavior
- lock behavior
- I/O and memory signals
- workload shape
- risk-aware intervention design

That is why tuning deserves its own phase.

---

## 2. “Slow” is only the symptom

One of the biggest mistakes in tuning is to treat “slow” as the cause.
It is not.

Real causes may include:
- a poor execution plan
- a good plan overwhelmed by bad data distribution
- lock contention
- too much random I/O
- excessive sort or temp-table work
- memory pressure
- over-indexed writes
- application-level transaction design problems

So the first tuning move is not to change something.
It is to classify the bottleneck.

---

## 3. Bottleneck classification

A useful first-principles framing is:

```text
what is the dominant limiting factor right now?
```

Usually the answer fits one main category:
- plan / access-path issue
- contention / lock issue
- I/O issue
- CPU/work issue
- memory/temp-structure issue

This is powerful because each class points to a different intervention path.

Examples:
- plan issue -> inspect indexes, cardinality, query shape
- contention issue -> inspect transaction scope, write order, locking pattern
- I/O issue -> inspect page access, scans, storage pressure, cache behavior
- memory issue -> inspect temp tables, sort buffers, buffer pool sizing

Without this classification, tuning becomes superstition.

---

## 4. Evidence before action

The correct tuning workflow is:

```text
symptom
  -> mechanism hypothesis
  -> collect evidence
  -> choose smallest justified change
  -> measure before/after
```

This matters because many changes are not free.
Adding an index may improve one read path but worsen write performance.
Raising a buffer may help one class of queries but increase memory pressure elsewhere.
Changing transaction scope may reduce waits but alter business semantics if done carelessly.

So evidence-backed tuning is both safer and faster in the long run.

---

## 5. Tools used together, not in isolation

Serious tuning rarely depends on a single tool.

### EXPLAIN / EXPLAIN ANALYZE
Shows plan and actual execution behavior.
Good for plan/path issues.

### Slow query log
Shows which query patterns dominate latency over time.
Good for workload-level prioritization.

### performance_schema / sys schema
Shows waits, lock issues, memory use, digest-level patterns, I/O pressure.
Good for connecting SQL to actual resource consumption.

### SHOW ENGINE INNODB STATUS and lock views
Good for contention, deadlocks, transaction state, and some engine-level clues.

The point is not tool memorization.
The point is correlation:
- query shape
- chosen plan
- actual runtime behavior
- waits and system state

That correlation is where correct diagnosis comes from.

---

## 6. Query anti-patterns as recurring waste

A large fraction of real tuning work is recognizing predictable bad patterns.

Examples:
- non-sargable predicates (function-wrapped indexed columns)
- correlated subqueries with explosive repeated work
- OR conditions across columns that make access paths weak
- broad range scans on hot paths
- non-covering access on extremely frequent lookups
- wide update/delete patterns causing unexpected locking and I/O

This is why tuning is partly a pattern-recognition discipline.

You are not solving a new physics problem every time.
Often you are removing a known class of waste.

---

## 7. Plan issues vs contention issues

A very important practical distinction:

### Plan issue
Symptoms usually point to:
- too many rows examined
- scan-heavy behavior
- wrong index path
- bad join order
- excessive sort/temp work

### Contention issue
Symptoms usually point to:
- waits under concurrency
- lock timeout / deadlock
- throughput collapse only under load
- query itself may be fine when run alone

This distinction is crucial because engineers often misdiagnose contention as indexing or vice versa.

A query can be fast in isolation and still be disastrous under concurrency.
A query can also be slow in isolation because its plan is terrible even with no contention.

Tuning begins by deciding which world you are in.

---

## 8. Smallest safe change

A good tuning intervention is not necessarily the biggest change.
It is the smallest change that clearly targets the mechanism behind the symptom.

Examples:
- add a composite index because actual execution shows excessive row examination
- rewrite a query to become sargable
- reduce transaction scope because waits show lock contention dominates
- drop redundant index because writes became too expensive
- avoid broad config changes if the issue is a single hot query

This mindset reduces blast radius and makes validation easier.

---

## 9. Workload-aware tuning

A query does not live alone.
A tuning decision should always ask:
- how often does this query run?
- under what concurrency level?
- what other workloads share the same tables/indexes?
- is this read-optimized fix going to damage writes?
- is this endpoint latency-sensitive or batch-oriented?

This is where architect thinking becomes different from isolated SQL tweaking.

The same SQL change may be excellent in one workload and harmful in another.

---

## 10. Application-layer mapping

For backend systems, database tuning often starts from application symptoms:
- API response spikes
- queue lag
- worker throughput collapse
- connection pool exhaustion
- timeouts under load

That means effective tuning often requires following the chain:

```text
endpoint symptom
  -> SQL digest(s)
  -> execution behavior
  -> waits/contention/I/O pattern
  -> smallest safe fix
```

This is why SQL tuning and backend architecture are tightly coupled.

Transaction scope, retry policy, query shape, and access pattern are all application design choices that manifest in MySQL performance.

---

## 11. Production symptom maps

### Symptom: endpoint slow only under concurrency
Likely classes:
- contention
- lock waits
- hot rows/ranges
- plan that degrades badly with larger concurrent working set

### Symptom: query always slow even in quiet system
Likely classes:
- poor plan
- scan-heavy access
- excessive sort/temp work
- missing or misaligned index

### Symptom: latency became unstable over time
Likely classes:
- plan drift from data distribution changes
- cache-temperature differences
- mixed workload interference

### Symptom: writes slowed after optimization work
Likely classes:
- over-indexing
- additional maintenance cost
- widened transaction scope or locking side effects

---

## 12. Suggested labs for this phase

### Lab 1 — classify slowness
Take one slow query and decide:
- plan issue or contention issue?
- what evidence supports that classification?

### Lab 2 — before/after index intervention
- run baseline EXPLAIN ANALYZE
- add index or change query shape
- remeasure and compare
- note any write-path trade-off

### Lab 3 — anti-pattern rewrite
- choose a non-sargable or suboptimal query
- rewrite it
- compare plan and actual execution

### Lab 4 — workload-level view
- use slow query log / digest views
- identify top offenders by total latency, not just individual query time

### Lab 5 — contention vs plan comparison
- compare one scan-heavy query and one lock-heavy scenario
- explain why their fixes differ fundamentally

---

## 13. Compact mental model

Use this chain:

```text
slow symptom
  -> classify bottleneck
  -> inspect plan + waits + workload evidence
  -> identify dominant mechanism
  -> choose smallest justified change
  -> verify before/after
```

---

## 14. Explain-back checklist

You should be able to explain:
1. why “slow” is not a diagnosis
2. how to classify a bottleneck before tuning
3. how plan problems differ from contention problems
4. why query anti-patterns matter so much
5. why tuning must be evidence-backed
6. why smallest-safe-change is a strong operational principle
7. why workload shape matters as much as isolated SQL text

If you can do that, tuning is becoming an engineering discipline instead of guesswork.
