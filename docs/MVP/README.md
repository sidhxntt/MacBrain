# MacBrain MVP Execution

This folder contains the phase-by-phase execution plan for the MVP. Build and verify one phase at a time; do not start the next phase until the current phase’s exit criteria pass.

## Execution order

1. [Phase 01 — App shell](./01-app-shell.md)
2. [Phase 02 — Global activation and permissions](./02-activation-permissions.md)
3. [Phase 03 — SQLite storage](./03-storage.md)
4. [Phase 04 — Ollama provider](./04-ollama.md)
5. [Phase 05 — Indexing](./05-indexing.md)
6. [Phase 06 — Retrieval and citations](./06-retrieval-citations.md)
7. [Phase 07 — Knowledge graph](./07-knowledge-graph.md)
8. [Phase 08 — Chat and memories](./08-chat-memories.md)
9. [Phase 09 — Live context and safeguards](./09-context-safeguards.md)
10. [Phase 10 — Hardening and release](./10-hardening-release.md)

## Global constraints

- Native Swift, SwiftUI, and AppKit only; no Flutter, Electron, React Native, or cross-platform UI framework.
- Local inference through Ollama; no hosted AI API in the shipped MVP.
- User-selected sources only; never silently index the whole Mac.
- SQLite is the single local storage foundation, including FTS5, vectors, and the lightweight graph.
- Every answer claim must be traceable to evidence or clearly marked as uncertain.
- Every destructive action requires confirmation and must be testable.

## Definition of MVP complete

A clean-machine user can install the native app, configure Ollama and lightweight models, select local sources, index them incrementally, ask a question from any application, receive a streamed cited answer, open the source, ask follow-ups, save/forget memories, and use the app without user data leaving the machine.
