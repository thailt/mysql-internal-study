# Phase 1 — Storage (10 minutes)

## The root problem

A database must store durable data on disk, but disk is far slower than RAM.

So the engine faces an unavoidable tension:

```text
Data must live durably on disk
but useful query performance requires memory-speed access whenever possible
```

InnoDB’s storage design is the answer to that tension.

---

## 1. Why pages exist
Rows are a logical concept.
But the storage engine needs a physical unit for reading and writing.

That unit is the **page**.

Why not row-by-row disk access?
Because storage hardware strongly prefers block-oriented I/O.
Reading or writing a single row directly would waste the device’s strengths and cause terrible latency amplification.

So InnoDB groups data into pages and treats pages as the fundamental unit of:
- storage
- cache
- I/O

This is the first big mental shift.

---

## 2. Buffer pool: RAM as a page cache
Once the system is page-based, the next question is obvious:

> can we avoid touching disk for hot pages most of the time?

That is what the **buffer pool** does.

It caches data and index pages in memory.

Important internal intuition:
- **free list** tracks unused pages available for loading
- **LRU list** tracks cached pages by recency/temperature behavior
- **flush list** tracks dirty pages that need to be persisted later

This lets InnoDB separate:
- logical access to data
from
- physical disk I/O timing

If a page is already in the buffer pool, reads become memory-speed.

---

## 3. Why B+ tree is the right access structure
Having pages in memory helps, but we still need to find the right page efficiently.

A full scan over large datasets is too expensive.
We need a structure that supports:
- point lookup
- ordered traversal
- efficient range scan
- small tree height
- page-friendly node organization

That is why B+ tree is such a good fit.

Each node can map naturally to a page.
So one tree step roughly corresponds to one page read in the worst case.

With wide fan-out, the tree remains shallow, so lookups remain cheap.

This is the key bridge between storage theory and real I/O cost.

---

## 4. Clustered index: the primary physical order
In InnoDB, the clustered index is not just “an index on the PK”.
It is the table’s main physical organization.

The leaf level of the clustered index contains the full row.
That means the primary key determines how rows are physically arranged at the leaf level.

Consequences:
- PK lookups are direct through the clustered tree
- PK design affects storage locality
- range scans on PK benefit from physical order

This is why PK selection is a storage design decision, not only a schema identity decision.

---

## 5. Secondary index and bookmark lookup
Secondary indexes exist because one physical ordering is not enough.
Applications query by many keys.

But InnoDB cannot store the full row redundantly in every secondary index leaf in the same way clustered storage does.
Instead, secondary index leaf entries point back logically via the primary key.

So a typical non-covering secondary-index read becomes:

```text
use secondary index to find matching key
  -> retrieve primary key from leaf entry
  -> traverse clustered index
  -> fetch full row
```

That is the **bookmark lookup** or double lookup.

This explains many performance patterns:
- covering indexes can be dramatically faster
- low-selectivity secondary indexes may still generate lots of clustered lookups
- reading many rows through a secondary path can become random-access heavy

---

## 6. Covering index intuition
If the index itself already contains every column the query needs, the engine may avoid going back to the clustered index.

That is why a **covering index** can help so much.

It turns:

```text
secondary lookup + clustered lookup
```

into:

```text
secondary lookup only
```

That reduces I/O and CPU overhead.

---

## 7. Page split and merge
B+ trees are not static.
Writes reshape them.

If an insert lands on a full page, the page may split.
If pages become sparse enough, they may merge.

This matters operationally because write patterns affect index maintenance cost.
Random insert patterns tend to scatter writes and trigger more structural changes than append-friendly patterns.

That is another reason key design matters.

---

## 8. Buffer pool and index design together
A common mistake is to think:
- buffer pool is a memory topic
- indexes are a query topic

In reality they are tightly connected.

Indexes determine:
- which pages get touched
- how many page reads are needed
- whether lookups become scattered or localized

Buffer pool determines:
- whether those page touches hit memory or disk

So storage performance is always a combination of:
- page access pattern
- access structure
- cache effectiveness

---

## 9. Application-layer implications
This phase matters directly for backend design.

Examples:
- poor PK design can worsen write behavior
- missing composite indexes can turn hot endpoints into scan-heavy paths
- low-selectivity indexes can mislead expectations
- non-covering index usage can create many extra clustered lookups

A Java/backend engineer who understands this phase sees beyond “add index” and starts asking:
- what pages will this query touch?
- is the lookup clustered or secondary?
- is this path covering?
- is this access pattern cache-friendly?

---

## 10. Production symptom map for this phase

### Symptom: read latency is high
Possible causes:
- poor buffer pool hit ratio
- too many scans
- secondary lookup explosion
- poor index coverage

### Symptom: write amplification seems high
Possible causes:
- too many indexes
- random insert pattern
- frequent page split activity

### Symptom: one query still slow despite “having an index”
Possible causes:
- low-selectivity index
- non-covering access still doing many bookmark lookups
- wrong composite index order

---

## The compact mental model

```text
disk is slow
  -> use pages
  -> cache pages in buffer pool
  -> use B+ tree to find pages efficiently
  -> clustered index stores full rows in PK order
  -> secondary index leads back to clustered index
  -> write patterns reshape the tree through split/merge
```

## What you should be able to explain after this phase
1. why pages are the natural I/O unit
2. why buffer pool is central to performance
3. why B+ tree fits a page-based engine
4. why clustered index is more than “just an index”
5. why secondary index often needs a bookmark lookup
6. why covering indexes help
7. why PK/index design changes real storage behavior
