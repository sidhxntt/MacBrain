# Features and Capabilities

## System-wide sidebar

`SidebarPanelController`, `SidebarPanel`, AppKit window policy, and SwiftUI workspace views provide a narrow panel on a chosen screen edge. The panel is resizable, focusable, dismissible, multi-display aware, and can remain above ordinary application windows within its defined scope. AppKit owns panel lifecycle and window level; SwiftUI renders the chat, sources, settings, onboarding, and memory surfaces. This split avoids asking a view hierarchy to solve display reconfiguration, focus, or Spaces behavior.

## Local chat and explicit context

`ChatStore` owns messages, streaming state, cancellation, session history, and user-visible errors. `ContextAttachment` records selected text, clipboard, active app/window, or repository facts with source, timestamp, size, expiry, and redaction state. Context is visible, bounded, removable before send, and scoped to the next request by default. MacBrain does not continuously collect screens, keystrokes, clipboard contents, browser data, or editor text.

## Knowledge library

Users choose connectors individually. Current connector families include folders, Markdown/plain text, PDFs, Git repositories, Apple Notes/Mail/Calendar/Reminders/Contacts, browser profiles, Messages, Photos metadata, Apple Books, and meeting transcript files. Connector health shows permission, item count, last successful sync, pause/resume, and failure state. A source is usable only after a verified committed generation, so chat never retrieves from a half-replaced scan.

## Evidence-grounded answers

`HybridEvidenceRetriever` combines lexical FTS5 matches, vector similarity, source diversity, recency, and graph-aware expansion where available. `EvidenceAcceptancePolicy` limits evidence to authorized, relevant, citation-capable records. Source cards contain title/type, location, date, excerpt, score, and stable citation ID. Search-only mode returns evidence without calling the model. The answer prompt requires uncertainty when evidence is weak or conflicting; `CitationValidator` rejects references that cannot map to a real excerpt.

## Local models, memories, and recovery

Ollama is the MVP inference backend. It is detected locally, configured separately for chat and embeddings, streamed with cancellation, and never requires a hosted default. Conversations and explicit memories are separate local records: a memory can be inspected, edited, exported, or forgotten and never pretends to be source evidence. If generation is unavailable, existing indexed search stays useful; if one connector fails, other committed sources remain queryable.
