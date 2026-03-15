# Phase 6 — Replication / HA / Operations (10 minutes)

## The root problem

Everything before this phase can still describe a single-node world.
But real systems eventually need more:
- more availability
- more recoverability
- more operational safety
- sometimes more read capacity

So the question becomes:

> how do we move from a single durable server to a production-ready database system?

That requires several distinct capabilities.

---

## 1. Binlog vs redo log
A very important distinction:

- **redo log** = local crash recovery for the server itself
- **binlog** = ordered change stream for replication and PITR

This distinction matters because many newcomers assume “if redo exists, why not replicate from that?”

The answer is that replication and recovery have different purposes.

---

## 2. Replication modes
Replication gives another server a copy of changes.
But the safety guarantees differ.

### Async replication
- source commits without waiting for replica apply/receipt guarantee
- fastest and simplest
- can lose latest source transactions on failover

### Semi-sync replication
- source waits for at least one replica acknowledgment
- higher latency
- stronger failover safety

So topology choice is an explicit business trade-off, not just a technical default.

---

## 3. Lag and parallelism
Replicas are not magical mirrors.
They can lag behind.

Lag may come from:
- network delay
- slow apply
- large transactions
- weaker replica hardware
- insufficient parallel apply

This is why replication health must always be observed, not assumed.

---

## 4. HA is more than “having a replica”
A replica exists.
So what happens if the source dies?

You still need answers to:
- who becomes new primary?
- how do clients reroute?
- how much data can be missing?
- what consistency guarantees does the business expect?

That is the HA problem.

Group Replication / InnoDB Cluster / Router are all attempts to make this more systematic.

---

## 5. Backup and PITR
Even perfect replication does not save you from:
- operator error
- application bug deleting correct data everywhere
- logical corruption being replicated faithfully

That is why replication is not backup.

Backups give restore points.
Binlogs then let you move forward in time to a precise recovery point.
That is **point-in-time recovery**.

---

## 6. Operations and incident response
Once MySQL is in production, internals knowledge must become a runbook.

Typical incident questions:
- are we saturated on connections?
- is lag growing?
- did a plan regression occur?
- are we blocked on locks?
- is failover needed?
- if disaster happened, what restore path exists?

This is why observability matters just as much as topology design.

---

## 7. Application/architecture implications
For an architect or backend engineer, this phase matters because:
- consistency expectations must match topology
- read-after-write assumptions may break on lagged replicas
- failover semantics affect business guarantees
- backup retention affects recovery objectives

So replication / HA / ops are not infra-only topics.
They feed directly into system design decisions.

---

## Production symptom map for this phase

### Symptom: stale reads from replica
Possible causes:
- replication lag
- read routing without consistency guarantees

### Symptom: failover lost recent writes
Possible causes:
- async replication topology
- insufficient acknowledgment guarantees

### Symptom: backup exists but recovery still weak
Possible causes:
- no tested PITR workflow
- no binlog retention alignment
- backup not validated

### Symptom: incident debugging is chaotic
Possible causes:
- no health-check sequence
- weak observability
- no operational runbook

---

## The compact mental model

```text
single node is not enough
  -> binlog propagates changes
  -> replication creates copies
  -> HA decides failover behavior
  -> backup + PITR enable true recovery
  -> observability makes operations survivable
```

## What you should be able to explain after this phase
1. why binlog and redo log are different
2. why replication lag matters architecturally
3. why HA requires explicit failover semantics
4. why replication is not backup
5. why runbooks and observability are first-class operational tools
