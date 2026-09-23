# Engineering implementation guide

This is the code-facing companion to [Features](features.md) and [Engineering challenges](engineering-challenges.md). It identifies the owning components, the safety boundary, and the available verification evidence. Paths use the current Swift target name `MacBrain`, which is also the published product name.

| Feature group | Primary ownership | Safety / failure boundary | Verification evidence |
| --- | --- | --- | --- |
| Sidebar and activation | `Services/SidebarPanelController.swift`, `SidebarPanel.swift`, `OverlayWindowPolicy.swift`, activation-bar and geometry helpers | AppKit owns window state; SwiftUI cannot silently alter panel level or display placement. | `SidebarPanelControllerTests`, `SidebarGeometryTests`, `OverlayWindowPolicyTests`, activation-bar tests. |
| Workspace and user state | `Stores/ChatStore.swift`, `SourceLibraryStore.swift`, `MemoryStore.swift`, `InferenceStore.swift`, `MainWorkspaceStore.swift` | `@MainActor` stores publish user-facing state; domain I/O remains in services/actors. | Store, workspace, chat, memory, onboarding, and preferences tests. |
| Local sources and consent | `Models/SourceConnector.swift`, `Services/SourceConnectors.swift`, Apple/browser/file connectors, `SecurityScopedLocalAccess.swift` | Every connector has an explicit type/configuration/status; failed or denied access is isolated to that source. | Source connector, browser profile, structured query, lifecycle, fresh-install, and adversarial tests. |
| Indexing and persistence | `LocalSourceCoordinator.swift`, `IndexingJobCoordinator.swift`, `LocalSourceRepository.swift`, `MacBrainDatabase.swift` | Actor-owned SQLite transactions commit complete source state; removal and failed refresh cannot expose a partial index. | Database, source-index commit, indexing-job, local-file-indexer, scheduler, and initial-sync tests. |
| Retrieval and scope | `HybridEvidenceRetriever.swift`, `ConnectorQueryService.swift`, `SourceQueryScope.swift`, `EvidenceAcceptancePolicy.swift` | Search sees only authorized committed sources; semantic/graph degradation falls back to lexical retrieval. | Lexical-first, hybrid-retrieval, evidence-policy, scope, connector-query, and graph tests. |
| Citations and answering | `StreamingChatResponder.swift`, `LocalKnowledgeResponder.swift`, `CitationValidator.swift`, `ChatCitationCard.swift` | Evidence is bounded before prompting; rendered citations must resolve to accepted evidence; search-only survives provider failure. | Streaming, citation-card, renderer, real-backend question, and prompt-barrage tests. |
| Inference and setup | `OllamaClient.swift`, `OllamaProvider.swift`, `InferenceProvider.swift`, `InferenceStore.swift`, `OllamaSetupView.swift` | Only a local Ollama endpoint is used; timeout/retry/cancellation are explicit and no cloud fallback is implied. | Ollama client/live integration/setup, inference store, and streaming tests. |
| Context and live-Mac routing | `ContextSafeguards.swift`, `LiveMacContextProvider.swift`, `LiveMacQueryRouter.swift`, `SystemQueryService.swift` | Context is request-scoped, visible, bounded, redacted, and independently disableable. | Context-safeguards, live-Mac context/router, system-profile, and fresh-install system tests. |
| Sessions, memories, and caching | `LocalChatSessionRepository.swift`, `LocalMemoryRepository.swift`, `ResponseCachingResponder.swift` | Memory is separately persisted and user-managed; cached responses include source revision rather than silently outliving source changes. | Chat-store/session, memory-store, response-cache, and database tests. |

## End-to-end request flow

```text
user query + optional visible context
        │
ChatQueryIntentRouter / LocalQueryPlanner
        │
SourceQueryScope + LiveMacQueryRouter
        │
HybridEvidenceRetriever → EvidenceAcceptancePolicy
        │                         │
        │                  search-only response
        ▼
StreamingChatResponder → OllamaProvider/OllamaClient
        │
CitationValidator → ChatStore → SwiftUI citation cards
        │
LocalChatSessionRepository / MacBrainDatabase
```

The important ordering is intentional: routing and source scope happen before retrieval; evidence acceptance happens before generation; citation validation happens before rendering; persistence receives the resulting local session state. No model path gains filesystem or connector authority.

## Verification boundary

`swift test` is the broad local regression command. It proves deterministic behavior covered by the test environment, not TCC dialogs, full-screen/Spaces behavior, a local Ollama installation, browser-profile format compatibility, or performance under a real personal corpus. Those conditions belong to the manual acceptance work in [Development and verification](development.md) and [Phase 10](phases/phase-10-hardening-release.md).
