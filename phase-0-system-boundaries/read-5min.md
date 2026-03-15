# Phase 0 — System Boundaries (5 minutes)

## The first-principles question

> Before asking how MySQL stores, locks, or recovers data, what is the system actually made of?

## Start from the problem
If you do not know where responsibilities live, every deeper topic becomes blurry.

You will confuse:
- SQL parsing vs storage work
- optimizer decisions vs engine behavior
- connection issues vs query issues

So the first thing to build is a map.

---

## 1. `mysqld` is the server process
MySQL server is centered around the `mysqld` process.
It accepts client connections, parses SQL, coordinates execution, and talks to storage engines.

---

## 2. SQL layer vs storage engine
A crucial architectural split is:

### SQL layer
- parser
- optimizer
- executor
- server-level connection/session behavior

### storage engine
- data access
- page/index structures
- locking/versioning internals
- durability mechanisms

This split is why MySQL can support pluggable engines conceptually.

---

## 3. Handler API
The SQL layer does not directly manipulate low-level engine internals for every access.
It talks through an abstraction boundary: the **handler API**.

That gives MySQL a clean bridge between:
- generic SQL processing
- engine-specific storage behavior

---

## 4. Query path
A simple mental path is:

```text
client connects
  -> sends SQL
  -> parser understands syntax
  -> optimizer chooses a plan
  -> executor drives the plan
  -> handler API calls engine
  -> engine touches pages/indexes/logs
  -> result returns to client
```

This path is the backbone for the whole roadmap.

---

## 5. Connection and thread model
At a high level, a client session maps into server-side connection handling and thread behavior.
This matters because some production issues are not “query logic” at all.
They are:
- too many open connections
- connection churn
- thread pressure

---

## Production meaning
This phase gives you the map needed to ask the right next question:
- is the issue about protocol/connection?
- about SQL planning?
- about storage engine behavior?

---

## Mental model to keep

```text
client/protocol
  -> SQL layer
  -> handler boundary
  -> storage engine
  -> durable storage
```

## If you remember 4 things
1. `mysqld` is the coordinating server process.
2. SQL layer and engine layer are not the same thing.
3. Handler API is the abstraction bridge.
4. Without this map, later internals topics become confusing.
