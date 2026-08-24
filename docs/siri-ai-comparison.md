# Notch Brain and Siri AI

## Positioning

Notch Brain is not intended to be a general-purpose operating-system assistant. It is a local-first, user-controlled work-memory product: it helps people search selected work sources, see the evidence behind answers, and manage what is remembered.

Siri AI is Apple’s broad personal assistant. It operates across Apple devices and system experiences, using personal context, onscreen awareness, app actions, and general world knowledge.

The distinction is therefore not “AI in a sidebar.” The distinction is a dedicated, inspectable work-memory layer.

> Give me an answer about my chosen work materials, show exactly where it came from, keep the model and data under my control, and let me manage or delete that work memory.

## Comparison

| Area | Notch Brain | Siri AI |
| --- | --- | --- |
| Primary job | Remember, search, and cite selected work sources. | Assist across Apple devices, apps, personal context, and the web. |
| Data scope | Only sources the user explicitly selects or captures. | System-level personal context plus application-provided context. |
| Privacy model | Local-only by default; no cloud model calls unless the user explicitly enables them. | On-device first, with Private Cloud Compute available for more complex requests. |
| Models | Planned user-selectable local models through Ollama, with a future bundled local backend. | Apple Foundation Models, system orchestration, and Private Cloud Compute. |
| Evidence | Retrieval-backed answers should include exact citations and source-opening actions. | Optimized for conversational assistance and actions; it is not a dedicated work-source citation product. |
| Interface | An always-available, edge-attached macOS work sidebar with its own chat tabs and local history. | A system-wide Siri, Spotlight, and context-menu experience across Apple devices. |
| Current implementation | A polished local sidebar and chat UI with mock local replies and in-memory chat tabs. | Apple’s production assistant platform. |

## The Notch Brain differentiator

Notch Brain is intended to provide all of the following together:

- User-selected source indexing rather than silent whole-Mac indexing.
- Local SQLite-backed search, retrieval, conversations, and memory controls.
- Local inference by default, initially through Ollama.
- Evidence-first answers with source citations and direct source opening.
- Explicit save, inspect, edit, delete, forget, and export controls for durable memories.
- A persistent, system-level work surface that remains beside the application the user is working in.

Apple Intelligence and Siri AI can be more general and more deeply integrated with the operating system. Notch Brain should instead be more inspectable and intentional for work: its value is that a user can see what was searched, what evidence supports an answer, what is stored, and how to remove it.

## Current product boundary

The current codebase implements the sidebar shell, local chat UI, local tab/history interactions, and deterministic mock replies. The full product described in the canonical documentation—selected-source indexing, local retrieval, citations, durable storage, and local model integration—is planned work, not yet implemented.

## References

- [Notch Brain PRD](./PRD.md)
- [Notch Brain architecture](./architecture.md)
- [Notch Brain privacy and security](./privacy.md)
- [Apple introduces Siri AI](https://www.apple.com/newsroom/2026/06/apple-introduces-siri-ai-a-profoundly-more-capable-and-personal-assistant/)
- [Apple Intelligence developer overview](https://developer.apple.com/apple-intelligence/)
- [Apple Intelligence privacy](https://support.apple.com/guide/iphone/apple-intelligence-and-privacy-iphe3f499e0e/ios)
