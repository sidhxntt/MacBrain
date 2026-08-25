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

- [x] Persist security-scoped bookmarks for selected folders.
- [ ] Define a connector protocol returning normalized documents and source metadata.
- [ ] Extract Markdown headings, titles, paths, dates, and offsets.
- [ ] Extract PDF pages and preserve page numbers.
- [x] Detect Git roots, index supported tracked files, and read branch/commit metadata.
- [ ] Add exclusions for secrets, credentials, dependency folders, build outputs, and user-defined paths.
- [ ] Hash content and skip unchanged files.
- [ ] Chunk text deterministically with overlap and stable IDs.
- [ ] Queue embeddings and graph extraction as cancellable background jobs.
- [ ] Prune sources when files are deleted or moved.
- [ ] Test malformed files, permission denial, duplicates, cancellation, restart recovery, and stale pruning.

## Exit criteria

Users can select folders, see progress, re-index only changed content, remove deleted files from search, and inspect source metadata sufficient for exact citations.

## Phase 2 connector implementation

The current MacBrain shell provides explicit local connectors for Notes, Mail, Calendar, Reminders, Contacts, Browser Profiles, Messages, Photos metadata, Apple Books, user-selected folders, and Git repositories. Browser Profiles is one explicit consent action: after the user confirms it, MacBrain discovers profiles in known local storage roots for Safari; Chrome, Chromium, Brave, Opera, Firefox, Arc, Vivaldi, Microsoft Edge, and other catalogued variants, then creates one source per discovered profile. It also detects unknown Chromium-compatible profiles only when their conventional profile directory contains local browser signatures such as `History`, `Bookmarks`, or `Preferences`. It indexes readable bookmarks, history, Reading List data, downloads, and optional current-tab snapshots where each browser exposes a stable local format or Automation API. Unsupported browser storage is never guessed. A Folder connector recursively indexes supported text, caption, Markdown, and PDF files, including hidden and secret files while excluding dependency and build output. A Git connector recursively indexes those same supported files and adds branch, commit, author, timestamp, and changed-file metadata. Nothing connects or syncs at launch: users select an individual connector and confirm before macOS permission is requested or local content is read. Messages and Books can require Full Disk Access, which appears as connector health instead of a silent failure. Connector records are persisted locally with health, pause/resume, last-successful-sync, and complete per-source deletion. Chat retrieval searches the normalized local documents only and displays source labels with its evidence.
