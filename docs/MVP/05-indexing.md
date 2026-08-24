# Phase 05 — Source Connectors and Incremental Indexing

## Goal

Index selected local knowledge sources safely, incrementally, and with citation-quality metadata.

## Supported MVP sources

- Markdown.
- Plain text.
- PDFs through PDFKit.
- User-selected folders.
- Git repositories, tracked text files, commits, repository, and branch metadata.

## Implementation sequence

- [ ] Persist security-scoped bookmarks for selected folders.
- [ ] Define a connector protocol returning normalized documents and source metadata.
- [ ] Extract Markdown headings, titles, paths, dates, and offsets.
- [ ] Extract PDF pages and preserve page numbers.
- [ ] Detect Git roots, index supported tracked files, and read branch/commit metadata.
- [ ] Add exclusions for secrets, credentials, dependency folders, build outputs, and user-defined paths.
- [ ] Hash content and skip unchanged files.
- [ ] Chunk text deterministically with overlap and stable IDs.
- [ ] Queue embeddings and graph extraction as cancellable background jobs.
- [ ] Prune sources when files are deleted or moved.
- [ ] Test malformed files, permission denial, duplicates, cancellation, restart recovery, and stale pruning.

## Exit criteria

Users can select folders, see progress, re-index only changed content, remove deleted files from search, and inspect source metadata sufficient for exact citations.
