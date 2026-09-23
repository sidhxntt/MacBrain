# Technology stack

MacBrain’s stack is selected for a local, responsive, evidence-first macOS experience—not for operating a hosted knowledge service.

| Layer | Technology | Role and trade-off |
| --- | --- | --- |
| Language and concurrency | Swift 6, actors, `async`/`await`, `AsyncStream`, `@MainActor` | Keeps slow I/O and streaming off the UI while giving explicit cancellation/isolation. It requires careful actor boundaries rather than shared mutable stores. |
| UI | SwiftUI | Renders chat, sources, onboarding, preferences, and workspace state. It is not asked to own macOS panel policy. |
| Desktop integration | AppKit `NSPanel`, screen/window APIs, `NSWorkspace` | Provides edge placement, focus, window levels, display handling, and active-app integration that SwiftUI alone does not model precisely. |
| Persistence | SQLite via `sqlite3` | Local transactional record for knowledge, sessions, memories, and jobs. It avoids a user-data server but requires migration/recovery discipline. |
| Keyword retrieval | SQLite FTS5 | Strong for identifiers, paths, filenames, and exact language. It is paired with semantic ranking rather than presented as conceptual search. |
| Semantic retrieval | Local vector representation and embedding provider | Finds paraphrase/conceptual matches. It is bounded and can degrade to lexical search. |
| Local inference | Ollama HTTP API | Model discovery, embeddings, and token streaming remain local. It adds an installation/model-memory dependency; no hosted fallback is implied. |
| Source formats | Foundation/FileManager, security-scoped bookmarks, PDFKit, Git boundary, Apple frameworks | Preserves native metadata/provenance and permission boundaries instead of scraping a universal data dump. |
| Privacy controls | Scoped source config, Keychain direction, redaction, query scope | Keeps source access and request context explicit. Keychain/packaging hardening remains release work where applicable. |
| Verification | Swift tests, temporary SQLite databases, connector fixtures, stress and acceptance corpus | Tests deterministic policy while documenting the physical macOS/runtime checks they cannot prove. |

## Why hybrid retrieval

Personal knowledge mixes exact nouns and fuzzy recollection. FTS5 finds `PR-482`, path fragments, and literal quotes; embeddings find a decision expressed with different words. MacBrain fuses both and then applies source scope, deduplication, diversity, recency, and an evidence budget. The result is intentionally smaller than “everything that matched,” because a local model needs defensible evidence rather than an unbounded corpus dump.

## Why Ollama first, not forever

Ollama provides a practical local boundary for setup, model selection, embeddings, streaming, cancellation, and status. `InferenceProvider` prevents it from leaking into the UI/retrieval architecture. MLX/MLX-LM or `llama.cpp` can become future backends only after packaging, model licensing, signing, download, upgrade, hardware compatibility, and support expectations are intentionally designed.
