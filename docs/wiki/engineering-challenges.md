# Engineering challenges: how MacBrain earns trust locally

MacBrain may look like a sidebar, but its difficult work happens between a user granting narrowly scoped access and a model rendering a claim with a citation. The app must keep macOS desktop behavior predictable, personal data consentful, local search internally consistent, and model output tied to evidence.

Each section states the user-facing failure first, then the underlying engineering problem, the repository treatment, evidence, and the boundary that remains. The [implementation guide](implementation-guide.md) maps these claims to the owning code and tests.

## Useful terms

| Term | Meaning in MacBrain |
| --- | --- |
| Connector | An opt-in adapter that translates one local source family into normalized documents. |
| Committed generation | A complete, transactionally stored view of a source that retrieval is allowed to use. |
| Evidence | A retrieved excerpt with source provenance that may support a citation. |
| Context attachment | Visible, temporary user-approved input such as copied text or active-app metadata. |
| Memory | Explicitly managed durable information; it is not source evidence. |
| Lexical retrieval | Exact-term search, useful for identifiers, paths, and literal phrases. |
| Semantic retrieval | Vector similarity, useful for paraphrase and conceptual recall. |

## 1. Making a sidebar behave like a macOS feature, not a rogue window

### The problem

A panel must be reachable beside any application without stealing focus at the wrong time, disappearing across displays, intercepting clicks outside its visible shape, or becoming stranded after a screen change.

### Why it was difficult

SwiftUI is appropriate for the changing chat surface but does not own `NSPanel` lifecycle, window level, display frames, focus, Spaces, or global activation. Treating those as view-state details couples rendering to window-manager behavior that cannot be reliably unit-tested from a view hierarchy.

### How MacBrain handles it

`SidebarPanelController` owns AppKit construction and presentation. `OverlayWindowPolicy`, `SidebarGeometry`, `ActivationBarGeometry`, screen-provider abstractions, and click-shield policy make the rules explicit. SwiftUI views receive presentation state rather than deciding their own window level or coordinates. The activation bar and panel are independent surfaces with focused interaction policies.

### How it is verified

`SidebarPanelControllerTests`, `SidebarGeometryTests`, `OverlayWindowPolicyTests`, `ActivationBarGeometryTests`, `ActivationBarInteractionTests`, and `DesktopSidebarMetricsTests` exercise placement, policy, and state transitions without requiring a physical display.

### Remaining boundary

Automated geometry is not a substitute for manual acceptance across multiple monitors, changing scale/arrangement, full-screen apps, Spaces, and real shortcut permissions.

## 2. Refreshing personal data without half-built search

### The problem

A folder or connector scan may be slow, denied access, cancelled, interrupted, or observe files changing mid-run. If retrieval sees a partly replaced index, citations can point to stale or internally inconsistent documents.

### Why it was difficult

File discovery, hashing, chunking, embedding, graph extraction, FTS maintenance, stale pruning, and connector-health updates are separate operations. A source may also be deleted while an actor has yielded to SQLite. “Just replace the index” is unsafe when an interruption falls between document and chunk writes.

### How MacBrain handles it

`LocalSourceCoordinator`, `IndexingJobCoordinator`, `LocalSourceRepository`, and `MacBrainDatabase` normalize source data then commit a reconciled generation in SQLite transactions. Unchanged items stay local; changed and missing external IDs are reconciled only after a completed scan. A reentrancy check prevents an in-flight commit from resurrecting a source removed by the user. Health records last verified state and errors, so a failed refresh preserves prior verified search rather than presenting partial content as current.

### How it is verified

`SourceIndexCommitTests`, `LocalFileIndexerTests`, `IndexingJobCoordinatorTests`, `SourceLibraryStoreInitialSyncTests`, `FreshInstallConnectorE2ETests`, `ConnectorLifecycleTests`, and database tests cover transactions, cancellation/recovery, stale pruning, initial sync, and source removal behavior.

### Remaining boundary

The five-minute refresh scheduler is a deliberate MVP trade-off, not low-latency filesystem observation. A live acceptance run must still cover large/corrupt sources, bookmark revocation, and files changing while a real connector reads them.

## 3. Finding exact facts and remembered ideas in the same corpus

### The problem

“Where is PR #482?” needs exact matching; “what did we decide about annual billing?” may use none of the original words. A single ranking strategy makes one of those questions poor.

### Why it was difficult

Semantic matches can feel plausible while overlooking identifiers; lexical results can over-rank repeated boilerplate. Returning too much context also consumes unified memory and increases the chance that a model treats weak material as proof. Optional graph connections must improve recall without replacing direct excerpts.

### How MacBrain handles it

`HybridEvidenceRetriever` fuses lexical and vector results, falls back to lexical-only if a semantic path degrades, deduplicates adjacent/repeated chunks, and promotes diversity and recency. `EvidenceAcceptancePolicy` applies relevance, authorization, citation capability, and evidence-budget checks. Graph expansion is bounded and additive; `DeterministicGraphExtractor` provides a local deterministic starting point rather than an opaque graph service.

### How it is verified

`LexicalFirstRetrievalTests`, `HybridEvidenceRetrieverTests`, `EvidenceAcceptancePolicyTests`, `KnowledgeGraphTests`, `SourceQueryScopeTests`, and connector adversarial tests cover exact-match priority, fallback, eligibility, provenance, and scope boundaries.

### Remaining boundary

Ranking quality is corpus-dependent. Stress and production-prompt suites provide useful regression evidence, but representative personal corpora and latency/memory measurements on target hardware remain required for release confidence.

## 4. Keeping a fluent answer tied to real evidence

### The problem

A local model can generate polished prose that is unsupported, misattribute a source, or silently blend a saved memory with a document. Citation chips alone do not prove the answer they decorate is grounded.

### Why it was difficult

The model only sees a prompt, while the UI needs a stable source card, safe location, excerpt, and citation identifier. Streaming means the app must handle partial text, cancellation, failure, and source availability without fabricating a completed answer.

### How MacBrain handles it

`StreamingChatResponder` builds a bounded evidence/context prompt and streams through `ChatStore`. `CitationValidator` maps citations to accepted `RetrievalEvidence`; `ChatCitationCard` renders source metadata. The prompt policy asks for uncertainty under missing or conflicting support. `LocalKnowledgeResponder` and search-only routes remain useful when generation cannot run. `LocalMemoryRepository` is a distinct persistence path, so memories cannot automatically become evidence.

### How it is verified

`CitationValidator` coverage appears in `ChatCitationCardTests`, `StreamingChatResponderTests`, `AssistantMessageContentTests`, `RealBackendQuestionAcceptanceTests`, `ProductionPromptBarrageTests`, and `ContextSafeguardsTests`.

### Remaining boundary

Citation validation proves a shown citation resolves to an accepted excerpt; it cannot prove every sentence is a logically valid inference. Users must retain the ability to inspect the original source, and real-model acceptance remains necessary.

## 5. Running local models within a shared unified-memory budget

### The problem

On Apple silicon, macOS, active applications, model weights, token cache, embedding work, and MacBrain share one memory pool. A model that loads successfully can still make the desktop feel unusable or fail mid-response.

### Why it was difficult

Provider setup, chat streaming, embeddings, connection retries, timeouts, model roles, and system-profile questions all cross a local HTTP boundary. A local-only product cannot quietly fall back to a hosted provider when this fails.

### How MacBrain handles it

`InferenceProvider`, `OllamaClient`, `OllamaProvider`, `InferenceStore`, and `StreamingChatResponder` keep provider behavior behind typed status and error models. Chat and embedding models are selected separately; bounded evidence and prompt budgets reduce avoidable context growth. Streaming supports cancellation, watchdogs, and transient local-connection retry. If Ollama is absent or unavailable, the app reports recovery guidance and keeps evidence/search paths available.

### How it is verified

`OllamaClientTests`, `OllamaLiveIntegrationTests`, `OllamaSetupViewTests`, `InferenceStoreTests`, `StreamingChatResponderTests`, and system-profile tests exercise setup states, request/stream parsing, timeout and retry behavior, cancellation, and model-role handling.

### Remaining boundary

The exact model, RAM pressure, disk availability, and Ollama installation are machine-specific. The documented real-Ollama acceptance pass is still required; bundled inference is planned rather than implemented.

## 6. Offering useful live context without creating surveillance

### The problem

Clipboard, active-app, browser, selected-text, and screen features can improve a question—but a system assistant becomes invasive if it collects them continuously or hides what will be sent to a model.

### Why it was difficult

macOS authorization is fragmented: folders, Accessibility/Automation, Full Disk Access, contacts, photos, calendars, and browser storage each fail differently. A connector that has permission to read one source must not become broad permission to inspect the rest of the Mac.

### How MacBrain handles it

`ContextSafeguards`, `LiveMacContextProvider`, `SourceQueryScope`, `SecurityScopedLocalAccess`, and connector-specific status make consent and data category explicit. Attachments are visible, bounded, redactable, removable, and next-request scoped. Connectors start disconnected; permission failure becomes recoverable health. Browser profile discovery is explicit, source selection is separate from other live-context capabilities, and query scope excludes unauthorized sources.

### How it is verified

`ContextSafeguardsTests`, `LiveMacContextTests`, `SourceAccessRetrievalTests`, `BrowserProfileCatalogTests`, `BrowserProfileConnectorTests`, `FreshInstallSystemE2ETests`, and connector adversarial/end-to-end tests cover explicit attachment, access filtering, discovery, and clean-install behavior.

### Remaining boundary

TCC prompts and Full Disk Access cannot be fully simulated in unit tests. Release acceptance must confirm denial, revocation, reauthorization, and removal paths on a clean macOS account.

## Lessons that apply across the project

1. Persist a complete, verified local state before making it searchable.
2. Treat a local model as a fallible presentation layer, not an evidence store.
3. Make consent and scope visible in the product model, not an implied side effect.
4. Keep native window policy, retrieval policy, persistence, and inference behind separate testable boundaries.
5. Label automated evidence, manual runtime evidence, and future architecture separately.
