# Phase 1 — Storage

> Disk is slow, RAM is fast. How does MySQL organize data so reads and writes are practical?

## Core question
- Why pages?
- Why buffer pool?
- Why B+ tree?
- Why clustered and secondary indexes?

## Focus
- page I/O
- buffer pool
- dirty pages and flushing intuition
- B+ tree
- clustered index
- secondary index
- bookmark lookup
- page split / merge

## Primary reading
- Original source material: `../phase-2-storage-durability/README.md` sections 2.1 and 2.2
- Canonical sequence: `../roadmap-v2.md`
- Cheatsheet: `../cheatsheet.md`

## Expected outputs
- explain why node = page is a powerful design choice
- explain secondary index lookup end-to-end
- predict when a query likely causes more random I/O

## Lab prompts
- compare PK lookup vs secondary index lookup
- inspect index and buffer pool related metrics
- observe page and index behavior through EXPLAIN and stats

## Reading ladder
- `read-1min.md`
- `read-5min.md`
- `read-10min.md`
- `read-full.md`

## Production bridge
Typical symptoms mapped here:
- high read latency from poor access path
- too many scans
- memory pressure from undersized buffer pool
- excess I/O from poor index design
