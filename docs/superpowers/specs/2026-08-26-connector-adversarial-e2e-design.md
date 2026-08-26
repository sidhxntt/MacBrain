# Connector Adversarial End-to-End Audit Design

**Date:** 2026-08-26

## Goal

Prove, for every MacBrain connector, that grounded answers are factually supported, identify the correct source type, render accurate citations, reflect source changes, respect authorization, and never borrow facts from a colliding source. Any failure becomes a regression test and a production fix before the audit can pass.

## Scope

The matrix covers all eleven `SourceConnectorKind` values:

- Apple Notes
- Apple Mail
- Apple Calendar
- Apple Reminders
- Apple Contacts
- Browser Profiles
- Messages
- Photos metadata
- Apple Books
- Folder
- Git repository

Testing uses controlled synthetic records shaped like each connector's real `ConnectorDocument` output. This exercises the production database, chunking, lexical/hybrid retrieval, intent routing, response prompt, citation validation, and terminal streaming path without reading personal data. Existing connector adapter tests remain responsible for converting each macOS store into that document contract. An opt-in live Ollama pass uses the same controlled corpus to detect model-quality failures.

## Coverage Matrix

Each connector receives multiple targeted questions in every dimension:

1. **Facts** — exact unique names, values, dates, participants, and negative/missing facts must match the controlled record.
2. **Source type** — retrieved evidence and rendered source cards must identify the expected connector kind, not a generic or misleading file source.
3. **Citations** — every asserted controlled fact must cite a known evidence ID; rendered cards must resolve to the cited record and must never invent a fake file URL for an opaque connector identifier.
4. **Freshness** — after an update, deletion, or disconnection, old markers and old citation targets must disappear from retrieval and the answer.
5. **Permissions** — a source in `needsAuthorization` is ineligible for retrieval even if it has cached documents; restricted bulk-extraction and unconnected-source prompts must terminate without source access.
6. **Cross-source isolation** — deliberately colliding markers are placed in at least two source kinds. A prompt naming Mail, Notes, Calendar, Reminders, Contacts, Messages, Photos, Books, Browser, Folder, or Git may retrieve only the named kind. Generic cross-source questions may combine sources, but every contributing fact must retain its own citation.

The matrix records a stable case ID, connector kind, prompt, expected facts, forbidden facts, expected source type, access expectation, and mutation phase. A completeness test fails if any connector lacks any dimension or has too few adversarial prompts.

## Production Boundaries

### Retrieval eligibility

`LocalSourceRepository` supplies only eligible source IDs to retrieval. Removed and `needsAuthorization` sources are excluded from lexical, semantic, graph, and fallback searches. A failed source may retain its last successfully authorized snapshot; pausing sync does not silently delete already-authorized data.

### Explicit source scoping

A pure prompt scope resolver maps explicit connector language to one or more `SourceConnectorKind` values. The scope is applied to every retrieval path. It does not activate local retrieval by itself and does not affect general questions such as “How does Apple Mail work?” because routing still runs first.

### Honest citation metadata

Retrieval evidence carries the connector kind and the best real destination available from document metadata. File-backed records use actual file URLs; browser records use their stored web URL; records without a safe external destination remain valid provenance cards without pretending their opaque ID is a local path. Source cards display the connector type, and the parser accepts both linked and unlinked cards.

### Response validation

A grounded model answer is accepted only when its citation IDs are known. The audit additionally checks that expected controlled facts occur in the answer and forbidden colliding/stale facts do not. Missing or invented citations continue to use the bounded direct-evidence fallback.

## Test Layers

1. **Deterministic matrix:** Swift Testing parameterized integration cases seed temporary SQLite repositories and drive `StreamingChatResponder`. A controlled provider inspects the actual selected evidence and produces stable cited answers. This layer proves routing, eligibility, scoping, source metadata, citation rendering, mutations, and terminal behavior.
2. **Adversarial retrieval regressions:** Narrow tests reproduce each discovered bug before production changes are made.
3. **Live Ollama quality barrage:** Opt-in tests run controlled connector facts through the actual configured chat and embedding models with bounded concurrency and deadlines. Failures are classified as routing/retrieval/citation defects or model-quality misses; neither category is reported as a pass.
4. **Full verification:** Run the focused matrix, the complete deterministic suite, the live Ollama barrage, and the relevant concurrency sanitizer. Update the stress report with per-dimension and per-connector counts.

## Completion Criteria

The work is complete only when:

- all eleven connectors have direct executable coverage for all six dimensions;
- every generated matrix case terminates and all expected/forbidden fact assertions pass;
- source-kind and citation-card assertions prove correct provenance;
- update, delete, disconnect, and authorization-revocation cases prove no stale leakage;
- named-source prompts cannot retrieve a colliding connector;
- all deterministic tests pass;
- the live controlled barrage passes with no inaccurate answer, citation failure, leakage, hang, or timeout; and
- the final audit maps every requirement above to current command output or a named passing test.
