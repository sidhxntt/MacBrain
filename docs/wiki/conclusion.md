# Conclusion: the through-line from panel to evidence

NotchBrain starts with a narrow promise: a user should be able to ask about selected local knowledge from beside their work, without turning their Mac into an unbounded data source or their model into the authority on what is true.

The build order is the architecture. The native panel comes first because system-level UX must be predictable. Explicit permissions and transactional local storage come next because retrieval cannot be trustworthy if a source is invisible, partial, or stale. Local inference comes after evidence can be bounded, and memories remain separate so continuity does not become fabricated provenance. Live context and broader connectors grow only through the same consent, scope, and failure rules.

## Core conclusions

- **The local database is the record of searchable knowledge.** Connectors feed it through complete committed states; search does not read a connector’s partial in-flight scan.
- **Evidence is different from model prose.** Retrieval and citation validation preserve provenance, while the model is instructed to acknowledge uncertainty.
- **Consent is part of the data model.** A connector, a temporary attachment, and a macOS permission are not interchangeable grants.
- **Graceful degradation is a product behavior.** A failed connector, vector path, or local model must narrow available behavior rather than make unrelated knowledge disappear.
- **Honest evidence boundaries matter.** Unit tests demonstrate deterministic contracts; real macOS permissions, local model setup, window behavior, and personal-corpus quality need manual acceptance.

## Suggested reading paths

New contributors should read [Overview](overview.md), [Architecture](architecture.md), and [Engineering challenges](engineering-challenges.md). Engineers changing a feature should start at the [implementation guide](implementation-guide.md), then read its relevant [phase narrative](index.md#how-notchbrain-was-built) and tests. Release work should use [Development and verification](development.md), the stress/acceptance artifacts, and [Roadmap](roadmap.md) rather than treating a test run as the complete operational story.

NotchBrain is therefore best understood as an explicit local-knowledge architecture: source access, committed storage, scoped retrieval, evidence, inference, and user-visible control remain separate on purpose. That separation is what allows richer connectors and future actions to be added without erasing the product’s privacy and provenance contract.
