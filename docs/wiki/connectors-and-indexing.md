# Connectors and incremental indexing

## Consent before discovery

MacBrain indexes nothing at first launch. A user chooses an individual connector or source, understands what it reads, grants its relevant access, and can pause, reauthorize, or delete it. Folder access uses security-scoped local access; Apple data uses its platform boundary; browser-profile discovery begins only after an explicit connector action. Messages and Books may require Full Disk Access and report that need as health rather than circumventing it.

## One normalized document contract

Connector implementations translate native records to `ConnectorDocument`/source vocabulary with stable source identity, display metadata, content, date, location, and provenance. PDF pages, Markdown headings/offsets, repository facts, and browser/Apple labels survive normalization so the citation layer can still explain and open the origin.

## Index lifecycle

`LocalSourceCoordinator` reads a connector, applies exclusions, fingerprints relevant content, and delegates changed work to the local repository/database. `DocumentChunker` uses deterministic chunks and stable identities. `IndexingJobCoordinator` tracks resumable embedding/graph work. A reconciled source generation updates changed documents, prunes absent external IDs, refreshes health, and becomes visible atomically.

While a source refreshes, retrieval uses its prior verified state. An incomplete scan is not a new source generation. A paused source preserves prior local data but stops refresh; access revocation removes eligibility until reauthorization and successful sync; deletion removes documents, chunks, embeddings, and FTS records from retrieval.

## Exclusions and limits

The connector policy excludes dependency/build output and supports user exclusions. Do not interpret that as a universal secret scanner: users should explicitly exclude sensitive folders and the product must continue to improve detection/redaction boundaries. Content is redacted/bounded before prompt assembly and diagnostics. Connector health exposes item count, committed state, last success, and recovery error so users can judge freshness.
