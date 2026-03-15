# Phase 4 — Optimizer (10 minutes)

## The root problem

A SQL query is declarative.
It says what result is wanted, not how to get it.

So the database must decide the execution strategy.

That creates a search problem:

```text
one SQL statement
  -> many possible execution plans
  -> huge difference in cost between plans
  -> optimizer must choose one
```

This is why query performance is not determined only by schema or indexing.
It is also determined by the optimizer’s model of the world.

---

## 1. Candidate plans
Even a modest query can have several choices:
- full scan or index access
- which index to use
- whether to use a covering path
- which table to join first
- which join algorithm to apply

The optimizer’s job is not just to parse SQL.
Its real job is to choose among these plans.

---

## 2. Cost model
MySQL’s optimizer is cost-based.
It estimates the relative cost of plans using assumptions about:
- how many rows will be touched
- how much I/O work may happen
- how much CPU/filter/sort work may happen

This is why cost model intuition matters.
A plan is not chosen because it is elegant.
It is chosen because the engine believes it is cheaper.

---

## 3. Statistics and cardinality
Statistics are the optimizer’s map of the data.

Without decent cardinality/selectivity estimates, the optimizer cannot compare plans reliably.

Examples:
- if it thinks a predicate is highly selective when it is not, it may choose a bad index path
- if it underestimates join expansion, it may choose a terrible join order

So optimizer correctness depends heavily on estimate quality.

---

## 4. Join order as a first-class decision
In multi-table queries, join order can dominate cost.

If the engine starts from a highly selective table, later work shrinks.
If it starts from a huge low-selectivity table, later work may explode.

So a major optimizer responsibility is:
- searching join order space without trying every permutation exhaustively

This is where heuristics and pruning matter.

---

## 5. EXPLAIN and EXPLAIN ANALYZE
You need both perspectives:

### EXPLAIN
What the optimizer *expects* to happen.

### EXPLAIN ANALYZE
What *actually* happened when the query ran.

The delta between them is often where truth appears.

If the optimizer estimated 10 rows and actual was 100,000 rows, the plan may have looked cheap only because the model was wrong.

---

## 6. Optimizer trace
When the plan choice is non-obvious, optimizer trace answers:
- which alternatives were considered?
- what estimates were used?
- why was one plan chosen over another?

This is one of the best tools for learning optimizer behavior rather than guessing it.

---

## 7. How this differs from tuning
This phase is about:
- understanding plan selection
- reading optimizer reasoning
- understanding cost and cardinality

It is not yet the full operational tuning phase.
That comes later.

So here the emphasis is:
- why the engine believed this plan was right

Later the tuning phase asks:
- what production symptom did this plan create, and what is the safest intervention?

---

## 8. Application implications
For backend engineers, this means:
- a query can regress without code change if data distribution shifts
- an added index can still be ignored
- a low-selectivity leading column can sabotage a composite access path
- a bad join order can dominate endpoint latency

So plan literacy is essential.

---

## 9. Production symptom map for this phase

### Symptom: same query became slower over time
Possible causes:
- changed data distribution
- stale stats
- changed candidate plan ranking

### Symptom: index exists but not used as expected
Possible causes:
- low selectivity
- optimizer cost model prefers scan
- better competing plan exists

### Symptom: join query explodes in latency
Possible causes:
- wrong join order
- severe cardinality misestimate
- poor filter placement/selectivity

---

## The compact mental model

```text
SQL is declarative
  -> many possible execution plans
  -> optimizer estimates candidate costs
  -> statistics influence those estimates
  -> join order and access path dominate cost
  -> EXPLAIN shows the guess
  -> EXPLAIN ANALYZE reveals the truth
```

## What you should be able to explain after this phase
1. why the same SQL can produce multiple plans
2. why statistics are essential to plan choice
3. why join order matters deeply
4. why plan regressions can happen without code changes
5. why EXPLAIN and EXPLAIN ANALYZE must be used together
