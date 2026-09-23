# Features: the NotchBrain experience

This page separates the user-visible product surface from the source-level implementation. For owners, safeguards, and tests, use the [engineering implementation guide](implementation-guide.md).

## System-wide sidebar — implemented foundation

The AppKit-backed `SidebarPanelController` presents a focusable, resizable, dismissible edge panel while SwiftUI renders chat, sources, settings, onboarding, and memories. Geometry and activation policy are isolated from views so display changes, edge selection, panel focus, and click shielding do not become undocumented gesture behavior.

The boundary: a physical multi-display/Spaces acceptance run remains stronger evidence than unit tests alone.

## Local chat and temporary context — implemented foundation

`ChatStore` owns streamed messages, cancellation, recoverable errors, and session history. `ContextAttachment` makes selected text, clipboard, active app/window, repository facts, and supported live snapshots visible before a request. Attachments are size-limited, removable, redactable, and scoped to a request by default.

NotchBrain does not continuously read keystrokes, screens, clipboard history, browser data, or editor text. A source connection is not permission for those other data classes.

## User-selected knowledge sources — implemented foundation

The source library offers folders, Git repositories, Apple productivity data, browser profiles, Messages, Photos metadata, Apple Books, and meeting transcript files through individual connector records. Health describes access, item count, last successful sync, pause/resume, and failure state. Source content becomes searchable only after a successful local commit; one failed connector leaves other committed sources usable.

Availability is connector- and machine-dependent. Some sources require TCC, Automation, or Full Disk Access and report a recovery state instead of trying to bypass macOS.

## Evidence-grounded retrieval — implemented foundation

`HybridEvidenceRetriever` combines lexical and semantic candidates, applies deduplication, source diversity, recency, graph-aware expansion where present, and an evidence budget. `EvidenceAcceptancePolicy` rejects unsuitable records; `CitationValidator` ensures rendered citations refer to accepted excerpts. Search-only mode returns the evidence without invoking a model.

This is a defense against unsupported claims, not a guarantee that a local model will never make an incorrect inference. The prompt requires uncertainty when support is weak or conflicting.

## Local inference, memories, and recovery — implemented foundation

Ollama is detected and configured locally with separate chat and embedding models. Responses stream with cancellation and actionable setup/failure state; when inference is unavailable, local source search remains useful. Explicit memories live in a separate local repository and can be inspected, edited, exported, or forgotten. A memory may guide a response but never impersonates a cited source document.
