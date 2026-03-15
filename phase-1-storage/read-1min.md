# Phase 1 — Storage (1 minute)

## Core idea
Storage exists because disk is slow and RAM is fast.

A database engine must answer:

```text
How do we keep data on disk
but avoid paying disk cost for every read/write?
```

## The essential chain

```text
disk is slow
  -> read/write in pages
  -> cache pages in RAM
  -> buffer pool
  -> need efficient lookup structure
  -> B+ tree
  -> one table needs one primary physical order
  -> clustered index
  -> extra access paths point back to primary order
  -> secondary index + bookmark lookup
```

## Minimal vocabulary
- **page** = basic storage / I/O unit
- **buffer pool** = in-memory page cache
- **clustered index** = primary key tree whose leaf pages hold full rows
- **secondary index** = tree whose leaf pages hold primary keys
- **bookmark lookup** = secondary lookup, then clustered lookup
- **page split** = when a full B+ tree page must split during insert

## Production meaning
Most query speed begins here:
- scans vs indexed access
- random I/O vs cached access
- PK choice affects physical organization
- poor index design multiplies I/O

## Done when
You can explain:
1. why DB engines use pages
2. why buffer pool exists
3. why B+ tree fits page-oriented storage
4. why secondary index often needs one extra lookup
