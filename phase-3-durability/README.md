# Phase 3 — Durability

> Commit means something survived a crash. What exactly survived, and why?

## Core question
- What does COMMIT really mean on disk?
- Why do we need WAL?
- Why redo log instead of flushing data pages on every commit?
- Why checkpoint and doublewrite?

## Focus
- WAL
- redo log
- log buffer
- LSN
- checkpoint
- doublewrite buffer
- crash recovery flow

## Primary reading
- Canonical sequence: `../roadmap-v2.md`
- Cheatsheet: `../cheatsheet.md`

## Expected outputs
- explain the write path from memory to durable commit
- explain why redo log and data page flush are decoupled
- explain recovery after crash at several different points in the write lifecycle

## Lab prompts
- perform writes, inspect redo/checkpoint state
- kill/restart lab to reason about recovery
- compare transaction durability settings at a conceptual level

## Reading ladder
- `read-1min.md`
- `read-5min.md`
- `read-10min.md`
- `read-full.md`

## Production bridge
Typical symptoms mapped here:
- commit latency spikes
- recovery taking too long after crash
- checkpoint pressure
- redo saturation / flush pressure
