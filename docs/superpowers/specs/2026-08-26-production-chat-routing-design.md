# Production Chat Routing and Prompt Barrage Design

## Objective

MacBrain must behave like a production-grade local assistant across ordinary conversation, general knowledge, writing, reasoning, coding, live macOS questions, and questions about explicitly connected local data. A prompt must never surface unrelated local evidence, block indefinitely, or remain in a pending state. Every request must terminate as a successful answer, a deliberate policy response, a cancellation, or a concise actionable failure.

No finite corpus can prove that every possible natural-language prompt is covered. This design therefore combines deterministic routing invariants, a broad regression corpus, metamorphic prompt variants, concurrency tests, and a representative live-Ollama soak so newly discovered failures become permanent regression cases.

## Routing Architecture

Introduce a focused `ChatQueryIntentRouter` that classifies the current prompt and bounded conversation context into one of these intents:

- `casual`: greetings, thanks, conversational acknowledgements, and social small talk.
- `general`: public knowledge, explanations, brainstorming, writing, translation, summarization, math, and coding questions that do not request user-owned context.
- `liveMac`: volatile information about this Mac, such as memory, storage, power, uptime, running apps, active app, CPU load, and network state.
- `explicitLocal`: direct references to the user's connected sources, files, folders, notes, mail, messages, contacts, calendar, reminders, photos, browser history, repositories, or named local paths.
- `implicitLocal`: organization- or project-specific questions that lack explicit local wording but may be answerable from strongly matching indexed evidence, such as ownership, deadlines, handoffs, decisions, or named internal entities.
- `restricted`: privacy-sensitive extraction or access to unconnected/unauthorized data.

The router is deterministic, side-effect free, and independently testable. Existing privacy and live-Mac policies remain authoritative and run before inference.

## Retrieval Policy

Routing and evidence acceptance are separate decisions:

1. `casual` and `general` never query local sources. They go directly to Ollama with general-assistant instructions.
2. `liveMac` uses fresh system providers and does not search the source index. If a live capability is unavailable, MacBrain returns a bounded explanation rather than substituting stale indexed material.
3. `explicitLocal` uses hybrid lexical, semantic, and graph retrieval from only connected sources.
4. `implicitLocal` first runs a cheap lexical candidate check. Hybrid retrieval is allowed only when lexical evidence passes an absolute relevance gate. Semantic rank alone cannot activate local evidence.
5. `restricted` returns the existing policy response without querying sources or Ollama.

Retrieved evidence must pass an `EvidenceAcceptancePolicy` before it enters a prompt. Acceptance uses query-term coverage, lexical match quality, source diversity, and configured minimum scores. Rank position by itself is never treated as relevance. Empty, weak, or contradictory evidence is discarded.

If accepted evidence is present, the model receives a bounded evidence context and must cite claims. If the model omits or invents citations, MacBrain returns a short, human-readable limitation with at most three concise excerpts. It must not render raw source files, HTML pages, generated code, or an unbounded evidence dump.

## Conversation Context

Follow-up messages use a bounded recent history to resolve intent. A short follow-up such as “when?” or “who owns it?” inherits local intent only when the immediately preceding user/assistant exchange was grounded in accepted local evidence. Starting a new chat resets inherited intent. General follow-ups remain general.

The stored assistant message records whether it was grounded and which source identifiers were used. This routing metadata is internal and is not shown to the user.

## Response Lifecycle and Concurrency

All connector scans, retrieval, Ollama generation, and persistence remain asynchronous. User-facing chat has priority over background indexing:

- Retrieval and provider-status checks have independent deadlines.
- A non-cooperative retrieval task cannot delay model generation after its deadline.
- Response rendering uses stable identities and coalesced updates.
- Background indexing uses its durable queue and cannot hold the chat database path hostage.
- Each request has exactly one terminal transition: answered, policy response, failed, timed out, or cancelled.
- Cancellation closes network streams and releases `isSending` without replacing partial valid output with raw evidence.

Concurrent prompt tests verify that one slow request, sync, or retrieval cannot serialize unrelated chats.

## Prompt Barrage Corpus

Create a table-driven corpus with expected route, source behavior, and response invariant. It covers at least these families:

- Greetings, thanks, emotion, and small talk.
- General factual questions across science, history, geography, culture, and technology.
- Writing, rewriting, summarization, translation, brainstorming, planning, and tone changes.
- Arithmetic, logic, structured reasoning, and ambiguous questions.
- Coding explanations, debugging, code generation, and questions containing terms also found in local repositories.
- Live macOS memory, storage, power, CPU, uptime, apps, networking, and device identity.
- Explicit files, folders, notes, mail, contacts, messages, calendars, reminders, photos, browsers, and repositories.
- Implicit project names, people, ownership, dates, decisions, and handoffs.
- Follow-ups, pronouns, corrections, topic changes, and new-chat resets.
- Empty, whitespace, extremely long, Unicode, emoji, punctuation, misspelled, and multilingual prompts.
- Prompt injection, requests for secrets, unauthorized sources, and attempts to override local privacy rules.
- Ollama unavailable, model missing, malformed stream, first-token timeout, mid-stream stall, cancellation, and retry.
- Concurrent general, live-Mac, and local-source prompts while source sync and indexing are active.

Each canonical prompt has generated variants for case, punctuation, contractions, polite prefixes, common misspellings, and paraphrases. A fixed seed keeps failures reproducible.

## Test Layers

### Deterministic unit and integration barrage

Run hundreds of prompts using controlled providers and seeded local documents. Assertions cover:

- Expected intent and retrieval decision.
- Zero local-source access for general/casual/live/restricted routes.
- Accepted local evidence only for explicit or sufficiently relevant implicit routes.
- No unrelated source titles, excerpts, HTML, or code leakage.
- Valid citation identifiers for grounded claims.
- Exactly one terminal state and cleared sending state.
- Per-stage timeout behavior and cancellation cleanup.
- Stable response rendering under long and rapidly streamed content.

### Live Ollama soak

Run a smaller representative corpus against the configured local models. Use bounded concurrency rather than flooding Ollama beyond its configured parallelism. Record route, time to first token, total duration, terminal state, response size, citation validity, and error category. The soak fails on hangs, deadline breaches, empty successful responses, raw evidence leakage, or process-level UI starvation.

The live test is opt-in for normal development but is run explicitly for this hardening task.

## Acceptance Criteria

- Every deterministic corpus case reaches its expected route and terminal state.
- General and casual prompts perform zero local retrieval and reveal no local source content.
- Live macOS prompts use fresh system data and do not fall back to indexed sources.
- Explicit local prompts retrieve connected data; implicit local prompts require the relevance gate.
- Weak evidence never replaces a general answer.
- No response remains pending beyond its configured deadline.
- Concurrent requests are asynchronous and one stalled component does not block others.
- Long responses do not create sustained SwiftUI layout loops or unbounded memory growth.
- The full Swift test suite passes.
- The live Ollama corpus completes without hangs or raw-evidence contamination; any model-quality miss is recorded separately from routing/runtime failures.

## Diagnostics

Add privacy-safe structured events for intent, retrieval decision, evidence acceptance reason, stage durations, terminal state, and timeout category. Logs contain identifiers and counts, never prompt text or source excerpts. Test reports preserve the seeded prompt label and category so failures are reproducible without copying private user data.

## Scope Boundaries

This work hardens routing, retrieval acceptance, response lifecycle, and local-model integration. It does not attempt to make an 8B local model match every factual or reasoning capability of hosted frontier models, add internet browsing, or weaken source authorization. Model-quality limitations are reported honestly while application routing and reliability remain deterministic.
