# Notch Brain Model Support

## MVP backend

Ollama is the required MVP inference backend. The app detects whether its local service is reachable, guides installation when absent, offers a recommended chat model and embedding model, tests both, streams generation, and supports cancellation. No cloud inference is used by default.

The rest of the app depends on a provider-neutral interface:

- list/check model availability;
- embed batches with cancellation;
- stream chat deltas with usage/error metadata;
- stop generation;
- report model capabilities and approximate resource needs.

## Model roles and profiles

| Profile | Chat role | Intended use |
|---|---|---|
| Light | 3B–4B quantized | commands and simple questions |
| Balanced | 7B–8B quantized | default RAG answers and summaries |
| Deep | 14B quantized | complex cross-document synthesis |

The embedding role is configured independently; `bge-m3` or `nomic-embed-text` are recommended starting points. Exact model tags remain configurable because availability changes.

## Hardware policy

The primary target is an Apple-silicon Mac with 24 GB unified memory. The app considers macOS, GPU, CPU, neural engine, Xcode, other apps, model weights, KV cache, embeddings, and context as one shared budget. It should recommend the balanced profile by default, warn before selecting a potentially oversized model, cap evidence and conversation context, and unload idle models where supported.

Memory pressure or slow generation must produce a clear recommendation: reduce model size, shorten context, stop another generation, or close competing workloads. Search-only mode remains available when generation cannot start.

## Prompt and streaming contract

Prompts contain system instructions, the user query, bounded conversation history, authorized live context, and evidence with stable citation IDs. The answerer must distinguish evidence from inference and state when evidence is missing or conflicting. UI state handles partial output, cancellation, timeout, provider failure, and retry without duplicating messages.

## Setup and recovery

Missing Ollama, missing models, incompatible model responses, connection refusal, timeout, cancellation, and memory pressure are separate actionable states. Setup must never block browsing existing indexed sources. A provider failure cannot corrupt conversations or indexing state.

## Future backends

Bundled MLX, MLX-LM, or `llama.cpp` may later implement the same provider contract for a zero-dependency experience. Model download, licensing, packaging, signing, hardware compatibility, and upgrade behavior must be solved before promotion from roadmap to MVP scope.
