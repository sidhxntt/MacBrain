# MacBrain Documentation

## Local AI setup

MacBrain uses Ollama only through `127.0.0.1`. It never needs a hosted AI account or API key. By default it also knows a bounded local system profile—current account display name, Mac/chip, memory, macOS, disk capacity, locale, and time zone—without indexing personal content. See [Phase 04 — Ollama and Local Model Setup](./MVP/04-ollama.md) for setup, privacy boundaries, and manual acceptance steps.

This is the self-contained source of truth for MacBrain, a native macOS, local-first AI memory and work assistant with a system-wide edge sidebar.

Documentation path in this workspace: `docs/`

## Read in this order

1. [Product requirements](./PRD.md) — product promise, users, scope, examples, and success criteria.
2. [Architecture](./architecture.md) — implementation boundaries, data flow, persistence, retrieval, and testing seams.
3. [Privacy and security](./privacy.md) — non-negotiable data handling and permission rules.
4. [Model support](./model-support.md) — Ollama MVP behavior, hardware limits, and future inference backends.
5. [MVP execution](./MVP/README.md) — the ordered ten-phase build plan.
6. [Beta metrics](./beta-metrics.md) — measurable validation and release gates.
7. [Beta release guide](./release.md) — signing, privacy, recovery, and clean-machine acceptance.
8. [MacBrain and Siri AI](./siri-ai-comparison.md) — product positioning and scope comparison.
9. [Post-MVP roadmap](./superpowers/plans/2026-08-23-notch-brain-post-mvp.md) — future work, not MVP requirements.
10. [Agentic macOS action layer](./todos/agentic-action-layer.md) — post-MVP Phase 6 plan for user-authorized system and app actions.

## Relative MVP difficulty

Difficulty is relative to this project’s current native macOS, local-only scope.

| Phase | Area | Difficulty | Why |
|---|---|---:|---|
| 01 | App shell | 4/10 | Native window, navigation, and visual polish are contained. |
| 02 | Global activation and permissions | 7/10 | AppKit overlay behavior, focus, and macOS permission states are platform-sensitive. |
| 03 | SQLite storage | 6/10 | Schema migrations, durability, and recovery need discipline but are well-bounded. |
| 04 | Ollama provider | 8/10 | Local model availability, streaming, cancellation, hardware limits, and setup failure paths. |
| 05 | Indexing | 8/10 | Incremental file discovery, connector permissions, deletion, provenance, and reliable background refresh. |
| 06 | Retrieval and citations | 10/10 | Hybrid ranking, evidence budgets, answer grounding, exact citations, and quality evaluation are core product risk. |
| 07 | Knowledge graph | 9/10 | Entity/relationship extraction and graph expansion must improve retrieval without adding false confidence. |
| 08 | Chat and memories | 5/10 | Conversation UX is straightforward; durable memories still need clear user control. |
| 09 | Live context and safeguards | 9/10 | Privacy boundaries, redaction, app integration, cancellation, and memory/resource limits must all hold together. |
| 10 | Hardening and release | 8/10 | Signing, clean-machine setup, recovery, privacy validation, and release reliability expose cross-phase failures. |

**Hardest:** Phase 06, then Phases 07 and 09.
**Easiest:** Phase 01, then Phases 08 and 03.

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
- [Beta release guide](./release.md)
- [MacBrain and Siri AI](./siri-ai-comparison.md)
- [MVP phase index](./MVP/README.md)
- [MVP phases 01–10](./MVP/01-app-shell.md)
- [MVP implementation plan](./superpowers/plans/2026-08-23-notch-brain.md)
- [Post-MVP implementation plan](./superpowers/plans/2026-08-23-notch-brain-post-mvp.md)
- [Agentic macOS action layer](./todos/agentic-action-layer.md)
