# Phase 06 — Hybrid Retrieval and Citations

## Goal

Return useful evidence quickly and generate answers that remain grounded in that evidence.

## Retrieval pipeline

```text
Query → normalize → FTS5 search + vector search → graph-aware scoring
      → deduplicate/diversify → token-bounded context → Ollama answer
      → citation validation and rendering
```

## Implementation sequence

- [x] Embed new and changed chunks through Ollama.
- [x] Implement FTS5 keyword search and vector similarity search.
- [x] Normalize and fuse scores with source diversity and recency controls.
- [x] Add bounded graph expansion once graph data exists; keep direct excerpts primary.
- [x] Deduplicate adjacent chunks and cap evidence by model context budget.
- [x] Define evidence objects with source title/type/path/date, excerpt, offset/page, score, and citation ID.
- [x] Assemble prompts requiring citation IDs, concise answers, and explicit uncertainty.
- [x] Add search-only mode that returns evidence without generation.
- [x] Validate that every rendered citation maps to an actual excerpt.
- [x] Test exact matches, semantic matches, low-confidence queries, duplicate sources, token limits, and conflicting sources.

## Exit criteria

The system returns initial sources before or alongside generation, answers with clickable citations, refuses to present unsupported claims as facts, and preserves citation accuracy through streaming and follow-ups.
