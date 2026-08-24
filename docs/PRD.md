# Notch Brain — Project Requirements Document

## 1. Product summary

Notch Brain is a native macOS application that provides a Claude Code-style AI sidebar available system-wide beside any application.

Product promise:

> Your Mac remembers. Ask from the sidebar.

The app is not primarily a generic chatbot or a notch utility. It is a local-first AI memory and work assistant that can retrieve information from the user's Mac, understand the user's current context, answer with evidence, and help perform follow-up actions.

The original notch concept has been replaced by a persistent, edge-attached sidebar inspired by the Claude Code panel inside VS Code.

## 2. Target users

- Developers working across multiple repositories, terminals, and documentation sources.
- Knowledge workers who need to recall decisions, emails, notes, and documents.
- Privacy-conscious users who want local AI and do not want their personal/work data sent to the cloud.

The first release should prioritize developers and knowledge workers rather than attempting to support every macOS user.

## 3. Core user experience

1. The user opens the sidebar using a global keyboard shortcut or an edge gesture.
2. A narrow panel slides in from the right or left edge of the screen.
3. The user asks a question by typing or dictation.
4. The app searches the local knowledge index and relevant live context.
5. Ollama or another local inference backend generates a concise answer.
6. The answer streams into the sidebar.
7. The answer includes clickable source citations.
8. The user can ask follow-up questions, open sources, copy the answer, save a memory, or perform an action.

The panel should remain compact for quick questions and expand into a larger workspace for long answers, source inspection, or multi-step tasks.

## 4. Core capabilities

### 4.1 System-wide sidebar

- Native macOS sidebar attached to a screen edge.
- Available above other applications.
- Global keyboard shortcut.
- Optional edge-hover or edge-gesture activation.
- Resizable width.
- Compact and expanded modes.
- Support for multiple displays and display changes.
- Correct focus, keyboard navigation, and dismissal behavior.
- Optional persistence while the user works.

### 4.2 Chat and conversation

- Streaming responses.
- Follow-up questions with conversation context.
- Conversation history stored locally.
- Copy, retry, stop generation, and clear conversation actions.
- Short answers by default with an option to expand.
- Explicit uncertainty when evidence is weak.
- Search-only mode that shows matching sources without generating an answer.

### 4.3 Local knowledge retrieval

The app should support a full local index of:

- Markdown and plain-text files.
- Obsidian vaults.
- PDFs and documents.
- Apple Notes.
- Git repositories.
- Git commit history.
- Selected local folders.
- Clipboard history, where enabled.
- Screenshots and OCR text, where enabled.
- Email, preferably in a later phase.
- Calendar and reminders, preferably as later action/context integrations.

The user must be able to choose which sources and folders are indexed.

### 4.4 Citations and evidence

Every knowledge-backed answer should show source chips or cards containing, where available:

- Source name.
- Source type.
- File path, note title, email sender, or repository.
- Date.
- Relevant excerpt.
- Match or confidence information.
- Action to open the original source in its native application.

Example:

> The client approved the annual plan on March 14.

Sources:

- Email — Sarah Chen — Mar 14
- Project brief — `Projects/Acme/plan.md`

The assistant should not present unsupported claims as fact.

### 4.5 Current-context awareness

The app should progressively support:

- Currently selected text.
- Clipboard content.
- Active application.
- Current window title.
- Current Git repository and branch.
- Current file in supported editors.
- Terminal output copied by the user.
- Screenshot or visible-screen context, subject to explicit permission.

Example behaviors:

- In a browser: summarize the page or compare it with local notes.
- In Xcode or VS Code: explain the current file using repository context.
- In Mail: summarize a thread and find related decisions.
- In Terminal: diagnose copied error output.
- In Finder: explain or organize selected files.

### 4.6 Memory controls

The user should be able to explicitly manage durable memories:

- “Remember that the client prefers weekly updates.”
- “Save this as a project decision.”
- “Forget what you stored about this.”
- “Show me everything you remember about Project Atlas.”

Required controls:

- Inspect memories.
- Edit memories.
- Delete individual memories.
- Delete all memories.
- Export memories.
- Clearly distinguish indexed source content from assistant-created memories.

### 4.7 Actions

Later versions may support:

- Create a reminder.
- Add a calendar event.
- Save a note.
- Draft an email.
- Create a GitHub issue.
- Open a source file.
- Generate a meeting brief.
- Turn an answer into a task list.
- Run a coding-agent task.

Actions that modify external data must use a confirmation card. Read-only actions can be immediate.

## 5. Example queries

- “What did we decide about the launch date?”
- “Find the email where the client mentioned the budget.”
- “Summarize all open issues in this repository.”
- “What was the conclusion from yesterday’s meeting?”
- “Have I discussed this person before?”
- “Which document contains the API requirements?”
- “Compare the latest proposal with the previous one.”
- “What tasks did I promise to finish this week?”
- “Explain this code using the project documentation.”
- “Draft a response based on the previous conversation.”

## 6. Recommended MVP scope

The MVP should include:

- Native edge-attached sidebar.
- Global shortcut.
- Streaming local chat.
- Ollama integration.
- Markdown, plain-text, PDF, and selected-folder indexing.
- Git repository indexing and basic repository detection.
- SQLite metadata storage.
- Full-text search and vector search.
- Hybrid retrieval.
- Source citations and source opening.
- Clipboard and selected-text context.
- Local conversation history.
- Basic memory save and forget commands.
- Local-only privacy defaults.

Defer email, screenshots, calendar actions, reminders, and autonomous coding actions until the core retrieval experience is reliable.

## 7. Non-goals for the first release

- Building a general-purpose operating-system agent.
- Supporting every email provider initially.
- Automatically indexing the entire Mac without user consent.
- Sending personal data to a hosted model by default.
- Building a large suite of generic notch widgets.
- Replacing a full IDE or terminal.
- Fine-tuning custom language models.

## 8. Hardware assumptions

Primary development machine:

- MacBook Pro.
- Apple M5 Pro chip.
- 24 GB unified memory.
- 1 TB SSD.

Unified memory must be treated as a first-class constraint. macOS, the GPU, CPU, neural engine, Xcode, browser, the sidebar, the model, and the model context all share the same 24 GB pool.

Recommended local model strategy:

- Default chat model: quantized 7B–8B model.
- Optional advanced model: 14B, usable when memory pressure is low.
- Avoid requiring 32B+ models initially.
- Embedding model: `bge-m3` or `nomic-embed-text`.

Approximate profiles:

| Profile | Model | Purpose |
|---|---|---|
| Light | 3B–4B | Intent detection and simple commands |
| Balanced | 7B–8B | Default RAG questions and summaries |
| Deep | 14B | Complex cross-document synthesis |

The application should:

- Detect available memory.
- Recommend compatible models.
- Monitor memory pressure.
- Unload idle models where possible.
- Limit retrieved context size.
- Warn users when a model may be slow.
- Keep embedding and chat models separately configurable.

## 9. Ollama and inference strategy

### Initial approach

The MVP may require Ollama. The app should detect whether Ollama is installed and provide guided setup:

1. Detect missing Ollama.
2. Explain why it is needed.
3. Guide or automate installation where appropriate.
4. Offer one-click download of a recommended chat model.
5. Offer one-click download of an embedding model.
6. Test the local connection.

### Long-term approach

Support both:

- Bundled local inference using MLX, MLX-LM, or `llama.cpp` for a zero-dependency experience.
- Optional Ollama backend for power users and flexible model selection.

The inference interface must be abstracted so replacing Ollama does not require rewriting the sidebar or retrieval layers.

## 10. Recommended technology stack

### macOS application

- Swift.
- SwiftUI for the UI.
- AppKit for system-level window and panel behavior.
- `NSPanel` or borderless `NSWindow` for the sidebar.
- `NSWorkspace` for active-application detection.
- macOS Accessibility APIs for selected text and application context.
- `NSEvent` for global shortcuts.
- Keychain for secrets and provider settings.
- FSEvents or filesystem watchers for incremental indexing.
- PDFKit for PDFs.
- Vision framework for OCR in a later phase.

SwiftUI should own the visual interface, while AppKit should handle edge attachment, always-on-top behavior, focus, resizing, multiple displays, and window lifecycle.

### Local AI

- Ollama initially.
- Local HTTP API with streaming responses.
- User-selectable chat models.
- User-selectable embedding models.
- Optional MLX or `llama.cpp` backend later.

### Storage and retrieval

- SQLite for metadata, conversations, memories, documents, chunks, and indexing state.
- SQLite FTS5 for keyword search.
- `sqlite-vec` or equivalent for vector similarity.
- Hybrid retrieval using keyword and vector results.
- Optional reranking for difficult queries.
- Incremental indexing with file hashes and modification timestamps.
- Stale-source pruning when files are deleted or moved.

### Source connectors

- Native Swift file and Markdown connector.
- PDFKit connector.
- Git CLI or Swift Git library.
- Apple Notes through AppleScript/JXA or available macOS automation APIs.
- Apple Mail/IMAP connector in a later phase.
- Clipboard via `NSPasteboard`.
- Screenshot/OCR through Screen Capture and Vision APIs in a later phase.

## 11. Suggested architecture

```text
Swift macOS application
├── SidebarPanel
├── ChatView
├── SourceCitationView
├── AppContextManager
├── PermissionManager
├── GlobalShortcutManager
└── LocalServiceClient

Local service
├── IndexCoordinator
├── SourceConnectors
│   ├── Files
│   ├── Markdown
│   ├── PDFs
│   ├── Git
│   ├── Apple Notes
│   └── Email
├── Chunker
├── EmbeddingProvider
├── HybridSearch
├── MemoryStore
├── ContextAssembler
└── OllamaClient

Local data
├── SQLite metadata database
├── FTS5 keyword index
├── Vector index
├── Conversation history
└── User-managed memory store
```

The sidebar UI must be decoupled from the RAG engine. The RAG engine should be replaceable or reusable through a local API, CLI, or MCP interface.

## 12. Potential reuse

Evaluate reusing or integrating [local-rag](https://github.com/sebastianhutter/local-rag) as the indexing and retrieval foundation. It already supports local Ollama embeddings, SQLite, hybrid search, Obsidian, email, code repositories, documents, and MCP tools.

If reused, Notch Brain should provide the system-level sidebar, conversation orchestration, live context, citations, memory controls, and product-quality macOS experience on top.

Do not tightly couple the UI to local-rag internals; use a stable local interface.

## 13. Privacy and security requirements

- Local-only operation by default.
- No user-data backend required.
- No cloud model calls unless explicitly enabled.
- Explicit source and folder permissions.
- User-configurable exclusions for secrets, credentials, build folders, and private directories.
- Keychain storage for tokens and provider settings.
- Clear explanation of every macOS permission requested.
- Search and memory deletion controls.
- Export controls.
- No silent indexing of the entire home directory.
- Confirmation before any action that modifies user data or external services.

## 14. Performance requirements

- Sidebar should open quickly and feel immediate even when the model is cold.
- Search should return initial sources before full answer generation where possible.
- Answers should stream progressively.
- Indexing must run in the background without freezing the UI.
- Indexing should be incremental rather than repeatedly processing entire sources.
- Model and memory pressure should be visible but unobtrusive.
- The app should degrade gracefully when Ollama is unavailable or a model cannot fit in memory.

## 15. Error handling

The app must handle:

- Ollama not installed.
- Ollama running but unavailable.
- Missing chat or embedding model.
- Insufficient memory.
- Permission denied for a source.
- Corrupt or unsupported document.
- Deleted or moved source.
- Empty or low-confidence search results.
- Model timeout or generation failure.
- Index corruption or migration failure.

Errors should be actionable and explain how the user can recover.

## 16. Estimated complexity

Complexity ratings:

- Sidebar UI and system window behavior: 5/10.
- Ollama integration: 4/10.
- Basic local RAG: 6/10.
- High-quality retrieval and citations: 8/10.
- Notes, email, and repository connectors: 8/10.
- Active-app and screen context: 9/10.
- macOS permissions, privacy, packaging, and multi-monitor behavior: 8/10.
- Production reliability and performance: 9/10.

Overall:

- Prototype: 5/10.
- Useful MVP: 7/10.
- Polished reliable product: 8/10.
- Full “understands everything on my Mac and can act” vision: 9/10.

Estimated effort:

- Prototype: 1–2 weeks.
- MVP: 4–8 weeks.
- Strong beta: 3–5 months.
- Polished product: 6–12 months.

## 17. Product positioning

Primary positioning:

> A private AI sidebar for everything you know and everything you’re doing.

Alternative descriptions:

- “Ask your Mac what you already know.”
- “The fastest way to retrieve and act on everything your Mac has seen.”
- “Your local work memory, always beside you.”

The durable differentiator is the combination of local memory, high-quality citations, current-screen context, Ollama-powered synthesis, and a system-level sidebar—not the sidebar alone.

## 18. Existing-product context

Products found during research include:

- [Nomi](https://github.com/rishabhcli/nomi): closest conceptual match; notch-native local knowledge assistant using Supermemory Local and Ollama, but very early-stage.
- [Notchi](https://github.com/cyrus-cai/notchi): polished notch AI utility that supports Ollama endpoints, notes, reminders, clipboard, screenshots, and coding agents, but does not appear to provide the complete cross-source RAG memory product described here.
- [Ultramemory](https://mac-ultramemory.com/): local memory across email, Slack, files, and screenshots with citations, but not primarily a sidebar product.
- [SecondBrain](https://openintelligence-labs.github.io/secondbrain-docs/): local memory daemon with vector search, BM25, knowledge graph, and MCP, but infrastructure rather than a polished sidebar.
- [Omodo](https://omodo.app/): local/private assistant across email, files, notes, and calendar, but not centered on the proposed sidebar UX.

The opportunity remains to combine these capabilities into a mature, native, sidebar-first product.

## 19. Definition of success

The MVP is successful if a user can:

1. Open the sidebar from any Mac application.
2. Ask a question about their local knowledge.
3. Receive a useful answer within a reasonable time.
4. See exactly which sources support the answer.
5. Open those sources directly.
6. Ask a follow-up question.
7. Add or remove a durable memory.
8. Use the product without sending data to the cloud.

The decisive product test is:

> The user asks, “What did we decide about the onboarding flow?”, and receives a concise, accurate answer with links to the exact note, email, and code discussion.

