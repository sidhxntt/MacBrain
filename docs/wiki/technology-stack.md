# Technology Stack

MacBrain’s stack is selected for one constraint: private, responsive retrieval has to work as a first-class macOS feature, not as a browser tab that uploads a knowledge base.

| Layer | Technology | Use | Why it belongs here |
| --- | --- | --- | --- |
| Language/concurrency | Swift 6, actors, `async`/`await`, `AsyncStream`, `@MainActor` | Streams tokens/progress, cancellation, UI isolation, background indexing. | Keeps slow filesystem/database/model operations off the rendering thread while providing typed cancellation/error boundaries. |
| Interface | SwiftUI | Sidebar, chat, citations, onboarding, source/memory/settings workspaces. | State-driven composition fits streaming answers and changing connector health. |
| Desktop integration | AppKit, `NSPanel`, `NSWorkspace`, `NSEvent`, screen APIs | Edge panel, global activation, active app, focus, displays, gestures. | SwiftUI alone does not offer the exact panel/window behavior a system-wide sidebar needs. |
| Local inference | Ollama HTTP API | Model discovery/setup, embeddings, streamed chat, cancellation. | Keeps default inference local and decouples model runtime from application UI/retrieval. |
| Relational storage | SQLite (`sqlite3`) | Sources, documents, chunks, embeddings, jobs, sessions, citations, memories, migrations. | Durable, transactional, single-user local storage with no server dependency. |
| Lexical retrieval | SQLite FTS5 | Exact terms, identifiers, filenames, commit/message text. | Fast, explainable keyword matches complement semantic similarity. |
| Semantic retrieval | Vector tables / `sqlite-vec`-equivalent design plus local embedding model | Meaning-based search over chunks. | Finds relevant paraphrases that literal keyword search misses. |
| Documents | Foundation/FileManager, security-scoped bookmarks, PDFKit | User-selected files/folders, persistent sandbox access, PDF extraction/page provenance. | Supports local sources while preserving consent and citation-quality locations. |
| Apple data | EventKit, Contacts, Photos, Apple Events where required | Opt-in connectors for calendars, reminders, contacts, photos and Apple apps. | Uses native permission-scoped APIs rather than scraping or cloud relays. |
| Browser/Git | Local profile readers, supported Automation paths, Git metadata/CLI boundary | Explicit profiles, bookmarks/history/tabs where stable; repository files/commits/branch facts. | Treats every integration as a connector with a real format, consent path, and failure state. |
| Security | Keychain, redaction, scoped permissions | Secret settings, token protection, content-safe diagnostics. | Source data and credentials must not leak through preferences or ordinary logs. |
| Verification | Swift Testing/XCTest-style suites, fixture repositories, temporary databases, stress/acceptance corpus | Pure logic, persistence, adversarial connectors, real-backend and manual acceptance. | Retrieval quality and privacy are product contracts, not visual-only features. |

## Why hybrid retrieval instead of one search method

FTS5 is strong for names, exact phrases, paths, identifiers and current commits. Embeddings are strong for paraphrase and conceptual recall. Neither alone handles the product’s mixed local corpus. MacBrain fuses both, diversifies sources, limits evidence to a context budget, and validates citations against the underlying excerpt. The result is a local RAG pipeline whose answer can state uncertainty instead of inventing a source.

## Why Ollama first, not permanently

Ollama provides a stable local HTTP boundary for model listing, model pull, embeddings, streaming and cancellation. It accelerates an MVP without binding the UI or retrieval system to one model family. `InferenceProvider` remains provider-neutral so MLX/MLX-LM or `llama.cpp` can become bundled backends later, after model licensing, packaging, signing, download, hardware, and upgrade concerns are solved.
