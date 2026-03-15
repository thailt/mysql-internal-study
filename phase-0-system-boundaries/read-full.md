# Phase 0 — System Boundaries (Full)

## 1. Why this phase comes before everything else

If you start learning MySQL by memorizing isolated components, you usually end up with fragmented knowledge.
You may know terms like:
- buffer pool
- redo log
- optimizer
- MVCC
- replication

but not know where they sit in the system or how they connect.

That is why this roadmap starts with boundaries.

Before asking:
- how does InnoDB store pages?
- how do locks work?
- how does crash recovery work?
- how does the optimizer choose plans?

we should first ask:

> what are the major layers of the MySQL system, and what responsibilities belong to each one?

This creates a mental map.
Once the map exists, later internals stop feeling like disconnected facts.

---

## 2. MySQL as a layered system

A useful first-principles view is:

```text
client / protocol
  -> connection and session handling
  -> SQL layer
  -> storage-engine boundary
  -> storage engine internals
  -> disk / memory / files
```

This is not meant to be a perfect source-code diagram.
It is a conceptual decomposition.

Each layer answers a different kind of question:
- how does the client talk to the server?
- how does the server understand SQL?
- how does it choose a plan?
- how does it actually fetch/modify data?
- how does it ensure correctness and durability at storage level?

This is the real starting point.

---

## 3. `mysqld` is the coordinating server process

The server process (`mysqld`) is the center of MySQL runtime behavior.

It is not “just the SQL parser”.
It coordinates multiple responsibilities:
- accepting client connections
- maintaining sessions
- parsing and validating SQL
- choosing execution plans
- driving execution
- interacting with storage engines
- participating in replication/binlog behavior

So when people say “MySQL”, they often mean a collection of subsystems inside `mysqld`, not a single simple layer.

Understanding that helps you avoid flattening everything into “the database did it somehow”.

---

## 4. Client/protocol and connection boundary

Every query starts before SQL parsing.
A client must:
- connect to the server
- authenticate
- establish a session
- send commands over the MySQL protocol

This matters because some production problems live here, not deeper inside the engine.

Examples:
- connection exhaustion
- too much connection churn
- session-level configuration issues
- client timeout behavior
- thread pressure from too many concurrent sessions

So phase 0 includes the outer shell of MySQL behavior, not just internal storage concepts.

---

## 5. SQL layer: from declarative text to execution plan

The SQL layer is responsible for making sense of the relational request.
A practical decomposition is:

### Parser
Turns SQL text into a structured internal representation.

### Semantic/preprocessing work
Checks validity, resolves objects, performs early validation.

### Optimizer
Chooses an execution plan from multiple candidates.

### Executor
Drives the chosen plan to actually produce rows or apply modifications.

This layer is about understanding and orchestrating *what should happen*.
It is not yet the same as physically storing and retrieving bytes on disk.

This distinction is extremely important.

---

## 6. Storage-engine boundary: where logical work meets physical work

Once a plan exists, the server still needs actual data access.
That means moving from logical relational operations into storage behavior.

This is where the storage-engine boundary matters.

The SQL layer says things like:
- scan this relation
- apply this filter
- look up matching rows
- update/delete/insert row data

The storage engine provides the concrete mechanics underneath:
- how pages are organized
- how indexes are structured
- how rows are versioned
- how locking is done
- how changes become durable

This division of responsibility is one of the most important concepts in MySQL architecture.

---

## 7. Handler API: why the boundary stays clean

The handler API is the conceptual bridge between SQL-layer logic and engine-specific storage behavior.

Why is this important?
Because it allows MySQL to preserve a separation between:
- generic relational processing
- engine-specific implementation details

So the SQL layer can remain relatively general, while the storage engine can specialize in:
- page and index layout
- locking semantics
- MVCC internals
- redo/undo details

Without understanding this boundary, it becomes hard to explain why:
- optimizer behavior belongs in one conceptual place
- InnoDB internals belong in another
- multiple engines were historically possible

The handler API is therefore more than a code-level abstraction.
It is a clue to the architecture itself.

---

## 8. End-to-end query path

A durable mental model is this:

```text
client sends SQL
  -> connection/session context already exists
  -> parser interprets statement structure
  -> semantic validation resolves objects
  -> optimizer chooses execution plan
  -> executor drives that plan
  -> handler API crosses into storage engine
  -> engine reads/writes/caches/locks/logs as needed
  -> rows or status result return upward to client
```

This path is the spine of the whole roadmap.

Each future phase zooms into one segment:
- storage -> page/index/cache mechanics
- concurrency -> transactions, MVCC, locks
- durability -> redo, checkpoint, recovery
- optimizer -> plan selection logic
- tuning -> diagnosing real-world slow behavior
- replication/ops -> running MySQL beyond one node

So phase 0 is not fluff.
It is the index page of the mental model.

---

## 9. Why MySQL and InnoDB are not identical concepts

In real production work, InnoDB is usually the dominant engine for OLTP.
That can tempt people to mentally collapse “MySQL” and “InnoDB” into one thing.

But conceptually they are not identical.

- **MySQL** includes protocol, sessions, SQL parsing, optimization, execution coordination, and integration with storage engines.
- **InnoDB** is the storage engine that supplies the low-level storage, locking, MVCC, and durability behavior for most modern workloads.

This distinction matters because later phases will dive deeply into InnoDB, but phase 0 explains why that deep dive sits under a broader MySQL server model.

---

## 10. Connection model and why it matters for operations

A lot of engineers assume all MySQL problems are query problems.
That is wrong.

Some issues are connection-model issues:
- too many client sessions
- short-lived connection churn
- poor connection pooling behavior
- thread pressure
- session-level state explosion

This is why phase 0 also establishes that the path starts at connection/protocol, not at execution plan.

In production, this helps distinguish:
- “the query is slow”
from
- “the server is overloaded by session behavior before query logic even matters much”

---

## 11. Why this phase matters to backend and architecture work

This phase improves debugging and design discipline.

It lets you ask better questions.

Examples:
- Is this a bad query plan or a connection storm?
- Is this a storage-engine locking issue or an optimizer issue?
- Is this behavior due to client/session configuration or due to data-access structure?

Knowing the boundary is the first step toward knowing which mechanism to inspect.

This is systems thinking in practice.

---

## 12. Suggested labs for phase 0

### Lab 1 — draw the query path
Without notes, draw the end-to-end path from client SQL text to storage engine and back.

### Lab 2 — map problem classes to layers
Take several production-like symptoms and classify them:
- connection exhaustion
- bad EXPLAIN plan
- lock wait timeout
- slow crash recovery
- replication lag

Ask: which layer owns this most directly?

### Lab 3 — compare SQL-layer vs engine-layer questions
Write two columns:
- questions answered by SQL layer
- questions answered by storage engine

This is a great way to solidify the boundary.

---

## 13. Compact mental model

Keep this chain:

```text
client/protocol establishes session
  -> SQL layer interprets and plans
  -> handler boundary crosses into engine
  -> storage engine performs physical work and guarantees
```

This one line is enough to orient almost every later topic.

---

## 14. Explain-back checklist

You should be able to explain:
1. what `mysqld` is conceptually responsible for
2. what belongs to connection/session handling
3. what belongs to SQL layer
4. what belongs to storage engine
5. why handler API matters as an architectural boundary
6. the end-to-end path of a query
7. why MySQL and InnoDB are related but not identical concepts

If you can explain these clearly, the roadmap now has a solid foundation.
