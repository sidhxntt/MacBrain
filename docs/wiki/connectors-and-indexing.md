# Connectors and Incremental Indexing

## Consent before discovery

MacBrain does not scan the home directory or enable connectors at launch. The user selects one connector/source, sees what it reads, grants only the relevant macOS permission, and can remove it later. Folder access uses security-scoped bookmarks; Apple connectors use their native permission boundary; browser profiles remain off until explicitly chosen. Messages and Books may require Full Disk Access, represented as health rather than silently bypassed.

## One normalized document contract

Every connector translates its native record into stable source identity, display metadata, content, date, location, and provenance. Markdown retains headings/offsets; PDFs retain pages; Git retains repository/branch/commit/author/changed-file facts; meeting captions discard timestamps before search. This lets the indexer, retriever, and citation card reason about one document/chunk vocabulary without losing the action needed to open the original source.

## Index lifecycle

`IndexingJobCoordinator` discovers supported content, applies exclusions, hashes it, skips unchanged items, chunks deterministically with overlap/stable IDs, and schedules local embedding/graph work for changed chunks. Source generations commit atomically. Queries use the last verified generation while a five-minute refresh is underway; an incomplete replacement is never exposed. Deletes/moves are pruned, a paused source preserves prior local content but stops refresh, revoked access removes retrieval eligibility until reauthorization and a successful sync, and source deletion removes its documents/chunks/embeddings from local retrieval.

## Important exclusions and limits

Credentials, SSH keys, environment files, token/config directories, build output, dependency caches, binaries, and user-configured paths are excluded. Exclusion and redaction happen before prompt assembly and diagnostics. Connector failure affects the connector, not the whole library; health reports item count, last success, permission failure, and committed state so the user knows whether search is relying on current or preserved evidence.
