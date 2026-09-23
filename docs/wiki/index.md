# NotchBrain documentation

NotchBrain is a native, local-first macOS knowledge assistant. It puts an edge-attached sidebar beside the work already on a Mac, searches only sources a user has explicitly connected, and produces evidence-grounded local answers.

This documentation is candid about delivery state:

- **Implemented** means the repository contains the relevant application code.
- **Verified** means focused automated tests or a recorded acceptance artifact exercise the behavior. It is not a blanket claim that every macOS permission or model/runtime combination has been manually exercised.
- **Planned** means a design or product direction exists but is not a current product guarantee.

## Start here

1. [Overview](overview.md) — problem, users, product boundary, and vocabulary.
2. [Architecture](architecture.md) — ownership boundaries, data flow, local persistence, and graceful-degradation rules.
3. [Features](features.md) — what a user can do today and what each capability deliberately does not do.
4. [Engineering challenges](engineering-challenges.md) — the hard problems, treatments, evidence, and remaining limits.
5. [Engineering implementation guide](implementation-guide.md) — source-level ownership and verification for every feature group.
6. [Technology stack](technology-stack.md) — technology choices and trade-offs.
7. [Connectors and indexing](connectors-and-indexing.md) and [retrieval, citations, and memory](retrieval-citations-memory.md) — the local knowledge pipeline.
8. [Privacy and permissions](privacy-and-permissions.md) — consent boundaries and recovery behavior.
9. [Conclusion](conclusion.md) — the product’s core architectural commitments and current evidence boundary.

## How NotchBrain was built

The build sequence separates native-shell risk, local-data correctness, and model behavior so a polished chat surface never hides an unsafe knowledge pipeline.

| Phase | Question it answers | Detail |
| --- | --- | --- |
| 1 | Can a native panel behave predictably across displays and apps? | [App shell](phases/phase-1-app-shell.md) |
| 2 | Can activation and macOS access remain explicit and recoverable? | [Activation and permissions](phases/phase-2-activation-permissions.md) |
| 3 | Can local data survive crashes without half-written search results? | [Storage](phases/phase-3-storage.md) |
| 4 | Can a local model stream and fail safely? | [Local inference](phases/phase-4-local-inference.md) |
| 5 | Can selected sources be refreshed without silently broadening access? | [Connectors and indexing](phases/phase-5-indexing.md) |
| 6–9 | Can evidence, conversations, memory, and live context remain bounded? | [Knowledge workflow](phases/phase-6-9-knowledge-workflow.md) |
| 10 | Can the product be hardened and released without overstating proof? | [Hardening and release](phases/phase-10-hardening-release.md) |

## Finding a topic

| If you want to understand… | Read… |
| --- | --- |
| Why a cited answer is different from a fluent answer | [Retrieval, citations, and memory](retrieval-citations-memory.md) and [Challenge 4](engineering-challenges.md#4-keeping-a-fluent-answer-tied-to-real-evidence) |
| Why indexing never exposes a partial replacement | [Connectors and indexing](connectors-and-indexing.md) and [Challenge 2](engineering-challenges.md#2-refreshing-personal-data-without-half-built-search) |
| How permissions and personal data are bounded | [Privacy and permissions](privacy-and-permissions.md) |
| Which class or actor owns a capability | [Engineering implementation guide](implementation-guide.md) |
| How to build, test, or publish the Wiki | [Development and verification](development.md) and [Wiki publishing](../wiki-publishing.md) |
| What is not yet a release promise | [Roadmap and delivery status](roadmap.md) |

## Documentation maintenance rule

When behavior changes, update the relevant implementation-guide row and feature/challenge narrative in the same change. Do not promote a planned connector, permission, model backend, or action into present tense merely because a design exists. Keep implemented, tested, and manual-runtime evidence separate.
