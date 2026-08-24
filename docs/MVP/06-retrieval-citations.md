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

- [ ] Embed new and changed chunks through Ollama.
- [ ] Implement FTS5 keyword search and vector similarity search.
- [ ] Normalize and fuse scores with source diversity and recency controls.
- [ ] Add bounded graph expansion once graph data exists; keep direct excerpts primary.
- [ ] Deduplicate adjacent chunks and cap evidence by model context budget.
- [ ] Define evidence objects with source title/type/path/date, excerpt, offset/page, score, and citation ID.
- [ ] Assemble prompts requiring citation IDs, concise answers, and explicit uncertainty.
- [ ] Add search-only mode that returns evidence without generation.
- [ ] Validate that every rendered citation maps to an actual excerpt.
- [ ] Test exact matches, semantic matches, low-confidence queries, duplicate sources, token limits, and conflicting sources.

## Exit criteria

The system returns initial sources before or alongside generation, answers with clickable citations, refuses to present unsupported claims as facts, and preserves citation accuracy through streaming and follow-ups.
