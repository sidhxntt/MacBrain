# Phase 08 — Chat, Conversations, and Memories

## Goal

Deliver the daily sidebar workflow: ask, stream, inspect evidence, follow up, and manage durable memories.

## Deliverables

- Streaming chat UI.
- Local conversation history.
- Source citation cards.
- Copy, retry, stop, clear, and open-source actions.
- Explicit memory save, forget, inspect, edit, delete, delete-all, and export.

## Implementation sequence

- [ ] Persist conversations/messages locally with model and timestamp metadata.
- [ ] Show retrieval results as early as possible while generation streams.
- [ ] Render markdown safely and map citation IDs to source cards.
- [ ] Add follow-up context with strict conversation and evidence limits.
- [ ] Implement explicit commands for memory operations; do not silently promote chat content to memory.
- [ ] Distinguish indexed source content from assistant-created memories in both storage and UI.
- [ ] Require confirmation for delete-all and export memories as portable JSON/Markdown.
- [ ] Test interrupted streams, app restart recovery, source opening, citation rendering, memory CRUD, and empty results.

## Exit criteria

A user can complete the core success test: ask about a local decision, receive a concise cited answer, open the exact source, follow up, save a memory, and later forget it.
