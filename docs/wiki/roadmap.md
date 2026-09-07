# Roadmap and Delivery Status

## Pre-MVP: foundations already established

The codebase and tests establish the native sidebar, activation geometry/policy, SQLite migrations, local Ollama client/provider, deterministic chunking, source contracts, lexical-first/hybrid retrieval, evidence acceptance/citation validation, local chat/memory records, context safeguards, source health, connector refresh, and connector adversarial acceptance coverage. These are foundations, not a claim that every connector or future action is universally available on every Mac.

## MVP: ten delivery phases

| Phase | Outcome | Engineering gate |
| --- | --- | --- |
| 01–02 | SwiftUI/AppKit shell; global activation and permissions | Correct panel/focus/multi-display behavior and recoverable permission denial. |
| 03 | SQLite foundation | Transactional migrations, durable records, recovery. |
| 04 | Ollama setup and streaming | Local-only connection/model checks, cancellation, memory-aware guidance. |
| 05 | Connectors/indexing | Explicit sources, stable provenance, incremental commits, stale pruning. |
| 06 | Retrieval/citations | Hybrid evidence, bounded prompts, clickable exact citations, uncertainty. |
| 07 | Knowledge graph | Additive entity/relationship expansion that does not displace direct evidence. |
| 08 | Chat/memories | Local conversations; explicit memory lifecycle and distinction from sources. |
| 09 | Live context/safeguards | Explicit, bounded, redacted context and resource/cancellation controls. |
| 10 | Hardening/release | Privacy, stress, clean-machine, signing, packaging and release gates. |

## Post-MVP: extensions that retain the same contracts

Apple Notes/Mail/Calendar/Reminders/Contacts, browser profiles/tabs, Messages, Photos metadata, Books, OCR/screenshots, richer editor/terminal context, external actions, and local coding-agent workflows fit through connector, context-provider, action, or `InferenceProvider` boundaries. They must preserve consent, a distinct provenance model, deletion semantics, redacted diagnostics, and confirmation for writes. Bundled MLX/MLX-LM/`llama.cpp` inference is also post-MVP until model packaging, licensing, signing, download, compatibility and upgrade behavior are production-ready.
