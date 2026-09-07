# MacBrain

Your Mac remembers. Ask from the sidebar.

MacBrain is a native, local-first macOS memory and work assistant. It brings an edge-attached sidebar to any application, retrieves only user-authorized local knowledge, assembles bounded evidence and context, and asks a local model to answer with citations.

## Read by intent

- [Product overview](overview.md) — problem, users, scope, and delivery status
- [Features and capabilities](features.md) — user-facing behavior and authority boundaries
- [Architecture](architecture.md) — runtime layers, state owners, data flow, and persistence
- [Technology stack](technology-stack.md) — every major technology, why it is used, and its role
- [Connectors and indexing](connectors-and-indexing.md) — consent, normalization, refresh, and deletion
- [Retrieval, citations, and memory](retrieval-citations-memory.md) — grounded answers and durable local records
- [Engineering challenges](engineering-challenges.md) — difficult problems and the implementation approach
- [Roadmap and delivery status](roadmap.md) — pre-MVP, MVP, and post-MVP work
- [Privacy and permissions](privacy-and-permissions.md) — local-first contract and macOS boundaries
- [Development and verification](development.md) — build, tests, acceptance, and documentation publishing

## Product contract

MacBrain does not silently scan the Mac, require a hosted AI account, or operate a product-owned user-data backend. A source becomes searchable only after the user selects it, grants the relevant access, and a complete local generation has been committed. The assistant distinguishes retrieved evidence, explicit live context, assistant-created memories, and model inference; only evidence can support a citation.

The current codebase contains both implemented foundations and planned work. This Wiki labels their status rather than implying that every PRD capability has already shipped.
