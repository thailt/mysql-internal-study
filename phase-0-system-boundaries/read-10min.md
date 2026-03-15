# Phase 0 — System Boundaries (10 minutes)

## The root problem

MySQL is often taught as a bag of features:
- parser
- optimizer
- InnoDB
- replication
- locking
- indexes

But that makes it hard to form a clean mental model.

The first-principles question is simpler:

> what are the major boundaries inside the system, and what responsibilities belong to each one?

Once that is clear, every later phase has a place to attach.

---

## 1. MySQL is a layered system
A useful high-level view is:

```text
client/protocol
  -> connection/session handling
  -> SQL layer
  -> storage-engine boundary
  -> storage engine internals
  -> disk / memory reality
```

This is the map you need before any deep dive.

---

## 2. `mysqld` as the coordinating process
The server process is not just a parser.
It coordinates:
- client connections
- session state
- SQL parsing
- optimization
- execution
- interaction with storage engines

So when people say “MySQL”, they often mean multiple logical subsystems inside the same server process.

---

## 3. SQL layer
The SQL layer is where MySQL interprets and plans relational requests.

A practical decomposition is:
- **parser**: understand syntax
- **preprocessing/semantic checks**: basic validity and object resolution
- **optimizer**: choose plan
- **executor**: drive plan execution

This layer is mostly about understanding *what to do* and *in what plan shape*.
It is not the same as physically storing rows.

---

## 4. Storage engine boundary
At some point, planning and execution need actual data access.
That is where the storage engine boundary matters.

The key idea is:
- SQL layer decides logical work
- storage engine performs physical data access and low-level guarantees

The **handler API** is the bridge between them.

That means a statement can be:
- parsed and planned in a generic SQL layer
- but executed against engine-specific storage mechanics underneath

---

## 5. Why handler API matters conceptually
The handler API is important because it explains how MySQL can keep:
- SQL semantics relatively generic
- storage behavior engine-specific

Without understanding this boundary, topics like:
- optimizer behavior
- InnoDB internals
- engine differences

all get mixed together in confusing ways.

---

## 6. Query flow as the roadmap backbone
If you want one durable picture, use this:

```text
client sends SQL
  -> parser builds understanding of statement
  -> optimizer chooses execution plan
  -> executor drives plan
  -> handler API calls storage engine access methods
  -> engine reads/writes/caches/logs
  -> rows/results return upward
```

Every later phase zooms into one part of this path.

- storage = how engine reads/writes data efficiently
- concurrency = how many transactions share data safely
- durability = how committed work survives crash
- optimizer = how plan is chosen
- tuning = how to diagnose bad behavior
- replication/ops = how system works beyond a single node

---

## 7. Connection model matters too
A lot of production confusion comes from treating every problem as “query execution”.
But some issues happen before or around query execution:
- too many connections
- session churn
- thread pressure
- bad client behavior

That is why protocol/connection/thread basics belong in phase 0.
They define the outer shell of server behavior.

---

## 8. Engine examples and why InnoDB matters
MySQL historically supported multiple storage engines.
The important point here is not feature trivia.
It is architectural separation.

In practice, InnoDB is the main engine for serious OLTP work.
So most later phases zoom into InnoDB.
But phase 0 explains why “MySQL” and “InnoDB” are related but not identical concepts.

---

## 9. Application/production implications
This phase matters because it lets you localize questions better.

Examples:
- query slow because of bad plan? -> optimizer/executor area
- connection exhaustion? -> connection/session area
- lock waits? -> engine/concurrency area
- crash recovery? -> durability area

This is basic systems thinking: know the boundary before debugging the mechanism.

---

## The compact mental model

```text
client enters through protocol/connection layer
  -> SQL layer interprets and plans work
  -> handler boundary crosses into storage engine
  -> engine provides physical storage, concurrency, durability
```

## What you should be able to explain after this phase
1. what `mysqld` is responsible for
2. SQL layer vs storage engine responsibilities
3. what handler API conceptually solves
4. the end-to-end path of a query
5. why phase 0 is required before deeper internals
