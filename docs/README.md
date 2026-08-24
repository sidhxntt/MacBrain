# Notch Brain Documentation

This is the self-contained source of truth for Notch Brain, a native macOS, local-first AI memory and work assistant with a system-wide edge sidebar.

Documentation path in this workspace: `/Users/sidhxntt/Desktop/Code/Products/NotchBrain/docs`

## Read in this order

1. [Product requirements](./PRD.md) — product promise, users, scope, examples, and success criteria.
2. [Architecture](./architecture.md) — implementation boundaries, data flow, persistence, retrieval, and testing seams.
3. [Privacy and security](./privacy.md) — non-negotiable data handling and permission rules.
4. [Model support](./model-support.md) — Ollama MVP behavior, hardware limits, and future inference backends.
5. [MVP execution](./MVP/README.md) — the ordered ten-phase build plan.
6. [Beta metrics](./beta-metrics.md) — measurable validation and release gates.
7. [Notch Brain and Siri AI](./siri-ai-comparison.md) — product positioning and scope comparison.
8. [Post-MVP roadmap](./superpowers/plans/2026-08-23-notch-brain-post-mvp.md) — future work, not MVP requirements.

## Authority and scope

The MVP is the first shippable product: native SwiftUI/AppKit shell, Ollama, user-selected local sources, SQLite-backed hybrid retrieval, citations, local conversations, memories, and explicit current-context capture. Email, screenshots, calendar/reminder actions, autonomous coding actions, and bundled inference are post-MVP.

When documents disagree, use this precedence:

1. User-approved requirements in [PRD](./PRD.md).
2. Implementation constraints in [architecture](./architecture.md), [privacy](./privacy.md), and [model support](./model-support.md).
3. MVP phase exit criteria in [MVP](./MVP/README.md).
4. Execution plans and roadmap notes, which must be updated when they conflict with the canonical documents.

All data stays on the Mac by default. No hosted model or silent whole-disk indexing is part of the MVP.

## Working vocabulary

- **Source**: a user-authorized file, folder, repository, or explicitly captured context item.
- **Document**: normalized source metadata and content tracked by the index.
- **Chunk**: bounded searchable text derived from a document.
- **Evidence**: retrieved chunks passed to the answerer and mapped to citations.
- **Memory**: assistant-created durable information, separate from indexed source content.
- **Context capture**: one explicit, visible addition such as selected text, clipboard text, active app, or repository/branch metadata.

## Complete document inventory

- [PRD](./PRD.md)
- [Architecture](./architecture.md)
- [Privacy](./privacy.md)
- [Model support](./model-support.md)
- [Beta metrics](./beta-metrics.md)
- [Notch Brain and Siri AI](./siri-ai-comparison.md)
- [MVP phase index](./MVP/README.md)
- [MVP phases 01–10](./MVP/01-app-shell.md)
- [MVP implementation plan](./superpowers/plans/2026-08-23-notch-brain.md)
- [Post-MVP implementation plan](./superpowers/plans/2026-08-23-notch-brain-post-mvp.md)
