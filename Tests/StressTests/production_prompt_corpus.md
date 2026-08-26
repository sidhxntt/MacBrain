# Production prompt barrage

The deterministic barrage in `ProductionPromptBarrageTests` expands a fixed, reviewable set of prompts into case, whitespace, and punctuation variants. It covers casual chat, general knowledge, writing, translation, math, coding, macOS how-to questions, live Mac state, explicitly connected sources, ambiguous internal projects, privacy restrictions, Unicode, prompt injection, timeout, cancellation, and concurrency.

The suite runs more than 300 prompts against local documents deliberately containing collisions such as Kubernetes, Netflix, Python, weather, and “what’s up.” Non-local routes must never expose the seeded `PRIVATE-LOCAL-MARKER` or source cards. Every request has a deadline and must finish in a terminal state.

The concurrency phase mixes fast, slow, live, local, restricted, stalled, and cancelled requests. It verifies that generation overlaps and that a stalled request does not serialize unrelated work.
