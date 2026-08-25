# Phase 6 Retrieval and Citations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Return grounded, source-diverse local evidence and require valid citations in generated answers.

**Architecture:** Keep SQLite and Ollama as the only retrieval dependencies. A `HybridEvidenceRetriever` actor will fuse FTS and vector candidates into bounded `RetrievalEvidence`, while the streaming responder injects citation-addressable evidence into its prompt and appends only validated citations to its finished response.

**Tech Stack:** Swift 6, actors/async sequences, SQLite FTS5, existing local vector store, Ollama embeddings/chat, XCTest.

---

### Task 1: Model evidence and retrieve hybrid candidates

**Files:**
- Create: `Sources/MacBrain/Models/RetrievalEvidence.swift`
- Create: `Sources/MacBrain/Services/HybridEvidenceRetriever.swift`
- Test: `Tests/MacBrainTests/HybridEvidenceRetrieverTests.swift`

- [ ] **Step 1: Write failing retrieval tests** for exact FTS matches, semantic vector matches, confidence thresholds, adjacent duplicate chunks, source diversity, recency ordering, and the context character budget.
- [ ] **Step 2: Run `swift test --filter HybridEvidenceRetrieverTests`** and confirm failure because the retriever does not yet exist.
- [ ] **Step 3: Implement minimal `RetrievalEvidence`, `EvidenceSearchResult`, and actor retrieval**: normalize the query, take ranked FTS/vector candidates, fuse reciprocal-rank scores, retain a modest recency boost, diversify sources, merge adjacent chunks, and stop before the context budget.
- [ ] **Step 4: Run the focused test target** and confirm it passes.

### Task 2: Make local source retrieval available to chat

**Files:**
- Modify: `Sources/MacBrain/Services/LocalSourceRepository.swift`
- Test: `Tests/MacBrainTests/HybridEvidenceRetrieverTests.swift`

- [ ] **Step 1: Add a failing repository integration test** that indexes documents and requests evidence through the repository.
- [ ] **Step 2: Run the focused tests** and confirm the integration API is unavailable.
- [ ] **Step 3: Add `searchEvidence(_:using:embeddingModel:)`** so the repository uses its SQLite database when present and falls back to explicit lexical evidence only when SQLite is unavailable.
- [ ] **Step 4: Run the focused test target** and confirm it passes.

### Task 3: Ground streamed answers with validated citations

**Files:**
- Modify: `Sources/MacBrain/Services/StreamingChatResponder.swift`
- Create: `Sources/MacBrain/Services/CitationValidator.swift`
- Test: `Tests/MacBrainTests/StreamingChatResponderTests.swift`
- Test: `Tests/MacBrainTests/CitationValidatorTests.swift`

- [ ] **Step 1: Add failing tests** that assert prompts list `[S1]` evidence, cite-only instructions, explicit uncertainty for weak retrieval, and that invalid model citation IDs are stripped while valid IDs remain clickable Markdown links.
- [ ] **Step 2: Run those focused tests** and confirm they fail before the feature exists.
- [ ] **Step 3: Build the system prompt from bounded evidence, validate emitted citation IDs after streaming, and append a `### Sources` list** linked to local file URLs when the evidence path is available.
- [ ] **Step 4: Run focused tests** and confirm they pass.

### Task 4: Verify the phase boundary

**Files:**
- Modify: `docs/MVP/06-retrieval-citations.md`
- Test: all relevant tests

- [ ] **Step 1: Mark only implemented Phase 6 checklist items complete.**
- [ ] **Step 2: Run `swift test`.**
- [ ] **Step 3: Inspect the diff and commit with `feat: add hybrid retrieval citations`.**
