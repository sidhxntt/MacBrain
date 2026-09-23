# MacBrain: a beginner’s guide

MacBrain is a local-first macOS memory and work assistant. It opens from a system-level sidebar, searches a user-approved local knowledge library, and uses a local model to answer with citations. Its promise is simple: **your Mac remembers; ask from the sidebar.**

## The problem it addresses

Useful work context lives across repositories, files, PDFs, Apple data, browser profiles, and fragments such as copied terminal output. Finding an answer often means remembering which application owns the fact, locating it with the right words, and then judging whether the result is current.

MacBrain makes that retrieval path explicit:

1. The user opens the sidebar and may attach temporary context.
2. The query is classified as a system question, source query, memory command, or knowledge question.
3. Only connected, locally committed sources are searched.
4. A bounded evidence set is assembled with provenance.
5. A local inference provider streams an answer or the app returns evidence directly in search-only mode.
6. The conversation stores the question, answer, and citation identifiers locally.

The product is not a whole-disk scanner, a hosted-chat account, or an autonomous computer-use agent. A future external write action must show a reviewable confirmation; the current product boundary is local read/retrieve and user-directed source opening.

## Who it is for

Developers can inspect a selected repository, recent commits, documentation, or copied error while staying in their current application. Knowledge workers can reconnect selected local material without forwarding it to a product-owned service. The first release prioritizes users who value provenance and local control over broad, automatic data collection.

## The architecture at a glance

```text
SwiftUI workspace + AppKit sidebar policy
                 │
       observable stores / typed services
                 │
 connectors → local source coordinator → SQLite + FTS5/vector search
                 │                             │
       explicit live context ───────────────────┘
                 │
      evidence policy → streaming local inference → cited response
```

SwiftUI renders the experience; AppKit owns panel and display behavior. SQLite is the durable local record. Connector and retrieval services work off the main actor. Ollama is the current local provider boundary, not a cloud fallback. See [Architecture](architecture.md) for the ownership rules.

## What is real now, and what is still a boundary?

The repository contains a substantial native shell, SQLite persistence, connector lifecycle, lexical/hybrid retrieval, evidence/citation policy, local Ollama integration, chat streaming, memory controls, and focused tests. Actual macOS permissions, local model availability, browser storage formats, and multi-display behavior still need machine-specific acceptance evidence.

Email/calendar/reminder writes, continuous screen or clipboard collection, bundled MLX/`llama.cpp` inference, and autonomous coding actions are planned directions, not current guarantees. The [roadmap](roadmap.md) and individual [phase narratives](index.md#how-macbrain-was-built) make those distinctions explicit.
