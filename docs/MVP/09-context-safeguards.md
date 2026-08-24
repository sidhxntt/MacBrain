# Phase 09 — Live Context and Resource Safeguards

## Goal

Add opt-in immediate context while protecting privacy, responsiveness, and 24 GB unified memory.

## MVP context

- Selected text.
- Clipboard content.
- Active application and window title.
- Current Git repository and branch.

## Implementation sequence

- [ ] Add visible context chips showing exactly what will be included in the next request.
- [ ] Add one-turn expiration and clear/remove controls for clipboard and selected text.
- [ ] Attach repository/branch context only when detected and relevant.
- [ ] Monitor memory pressure, model status, indexing queue, and database size.
- [ ] Cap retrieved context and conversation history before prompting Ollama.
- [ ] Unload idle models where supported and warn before selecting models likely to exceed memory.
- [ ] Test missing Ollama, model failure, memory pressure, oversized context, permission denial, and interrupted indexing.

## Exit criteria

Context is opt-in, visible, bounded, and removable; the sidebar remains responsive while indexing or generating; resource failures produce recovery guidance.
