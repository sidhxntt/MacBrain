# Engineering Challenges, Explained Simply

## 1. Making a sidebar work across macOS windows and displays

**Challenge:** A sidebar must feel available beside any app without behaving like an uncontrollable floating window. Focus, dismissal, Spaces, display changes, edge geometry and keyboard input all interact.

**Approach:** AppKit owns `NSPanel` lifecycle and display/window policy; SwiftUI only renders content. `SidebarPanelController`, geometry helpers and testable screen abstractions reconcile the panel as displays change. Global activation and edge interaction have focused policies rather than being embedded in a view gesture.

## 2. Indexing personal data without exposing a half-built answer

**Challenge:** A scan can be slow, cancelled, denied permission, or interrupted while documents are changing. Searching a partially replaced index would produce inconsistent citations.

**Approach:** Sources use committed generations in SQLite. Indexing hashes, chunks, embeds and writes in transactional stages; retrieval sees the last verified generation until a complete replacement succeeds. Health/status makes a permission error or stale source visible, while deletion removes configuration and local retrieval data.

## 3. Retrieval must find both an exact identifier and a remembered idea

**Challenge:** “PR #482” and “the decision about annual billing” demand different search behavior.

**Approach:** FTS5 handles literal language; embeddings handle semantic similarity. Hybrid fusion, deduplication, diversity/recency controls and evidence budgets turn candidates into a small defensible context. Graph expansion is additive, never allowed to replace direct excerpts.

## 4. A fluent model answer can still be wrong

**Challenge:** Local models can generate confident prose unsupported by a source.

**Approach:** Prompts carry evidence IDs and require uncertainty. Citation validation maps every rendered chip to a real excerpt. Search-only mode gives users an evidence-first route when generation is unnecessary or unavailable.

## 5. Local models share one unified-memory budget with the Mac

**Challenge:** On Apple silicon, macOS, the active IDE/browser, model weights, KV cache, embeddings and the app share memory.

**Approach:** Chat and embedding models are configured independently; the model policy recommends 3–4B, 7–8B, or 14B profiles by workload, caps context, reports setup/failure states, and leaves search-only usable when Ollama is absent or pressure is high.

## 6. “Current context” can become surveillance

**Challenge:** Clipboard, screen, browser and selected-text features are useful but dangerous when collected continuously.

**Approach:** Context is explicit, visible, scoped to the next request by default, size-bounded, removable, redacted before prompt/logging, and independently disableable. No continuous screen, key, clipboard, browser, or editor collection belongs in the MVP.
