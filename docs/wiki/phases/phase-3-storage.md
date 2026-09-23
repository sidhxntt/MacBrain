# Phase 3: local storage

## Problem

Sources, chunks, FTS rows, vectors, jobs, conversations, citations, and memories must survive restarts without allowing an interrupted write to corrupt retrieval.

## Treatment

`MacBrainDatabase` is an actor-backed SQLite foundation with ordered migrations and explicit transactions. `LocalSourceRepository` commits source generations and health together; FTS rows are removed explicitly where foreign-key cascades cannot manage a virtual table. Chat sessions and memories are distinct durable record types.

## Verification and boundary

Temporary-database, migration, transaction, source-index-commit, and session/memory tests cover the deterministic storage contract. Disk exhaustion, interrupted process termination, and upgrade validation should remain part of release acceptance.
