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
- [x] Define a connector protocol returning normalized documents and source metadata.
- [x] Extract Markdown headings, titles, paths, dates, and offsets.
- [x] Extract PDF pages and preserve page numbers.
- [x] Detect Git roots, index supported tracked files, and read branch/commit metadata.
- [x] Add exclusions for dependency folders, build outputs, and user-defined paths. Hidden and secret files remain indexed unless the user excludes them.
- [x] Fingerprint content and skip unchanged files.
- [x] Chunk text deterministically with overlap and stable IDs.
- [x] Persist cancellable embedding and graph-extraction background jobs for changed chunks. Graph extraction remains a no-op hook until Phase 7.
- [x] Prune sources when files are deleted or moved (moves are represented as delete + add).
- [x] Test malformed files, permission denial, duplicates, cancellation, restart recovery, and stale pruning.

## Exit criteria

Users can select folders, see progress, re-index only changed content, remove deleted files from search, and inspect source metadata sufficient for exact citations. The current change detector polls connected sources every five minutes while MacBrain is open; lower-latency filesystem events are intentionally deferred.

Changed file chunks enqueue durable local embedding work. Pending work is resumed after MacBrain has confirmed its configured local embedding model at launch; cancelled, failed, and completed job states remain persisted for inspection and recovery.

## Phase 2 connector implementation

The current MacBrain shell provides explicit local connectors for Notes, Mail, Calendar, Reminders, Contacts, Browser Profiles, Messages, Photos metadata, Apple Books, user-selected folders, and Git repositories. Browser Profiles is one explicit consent action: after the user confirms it, MacBrain discovers profiles in known local storage roots for Safari; Chrome, Chromium, Brave, Opera, Firefox, Arc, Vivaldi, Microsoft Edge, and other catalogued variants, then creates one source per discovered profile. It also detects unknown Chromium-compatible profiles only when their conventional profile directory contains local browser signatures such as `History`, `Bookmarks`, or `Preferences`. It indexes readable bookmarks, history, Reading List data, downloads, and optional current-tab snapshots where each browser exposes a stable local format or Automation API. Unsupported browser storage is never guessed. A Folder connector recursively indexes supported text, caption, Markdown, and PDF files, including hidden and secret files while excluding dependency and build output. A Git connector recursively indexes those same supported files and adds branch, commit, author, timestamp, and changed-file metadata. Nothing connects or syncs at launch: users select an individual connector and confirm before macOS permission is requested or local content is read. Messages and Books can require Full Disk Access, which appears as connector health instead of a silent failure. Connector records are persisted locally with health, pause/resume, last-successful-sync, and complete per-source deletion. Chat retrieval searches the normalized local documents only and displays source labels with its evidence.
