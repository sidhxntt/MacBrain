# Self-Contained Documentation Set Design

## Goal

Make Notch Brain’s documentation sufficient for an engineer or coding agent to understand the product, implement the MVP, validate it, and distinguish current requirements from post-MVP plans without needing missing documents or unstated context.

## Documentation model

The documentation has three layers:

1. **Canonical context** — `docs/README.md`, `docs/PRD.md`, `docs/architecture.md`, `docs/privacy.md`, `docs/model-support.md`, and `docs/beta-metrics.md` define the product and engineering contracts.
2. **MVP execution** — `docs/MVP/README.md` and its ten phase documents define the ordered implementation path and exit criteria.
3. **Planning history and roadmap** — `docs/superpowers/plans/` records implementation plans. The post-MVP plan describes future work and cannot silently add MVP requirements.

## New documents

### `docs/README.md`

The entry point. It identifies the product, absolute workspace documentation path, current MVP boundary, document authority order, implementation sequence, and links to every document in the set.

### `docs/architecture.md`

The technical source of truth. It defines the native macOS shell, service boundaries, data flow, persistence concepts, indexing and retrieval pipeline, context assembly, inference abstraction, concurrency expectations, failure boundaries, and test seams. It explicitly separates MVP components from future connectors and actions.

### `docs/privacy.md`

The privacy and security contract. It defines local-only defaults, source selection and permission rules, excluded content, context capture, retention and deletion, secrets, logging, export, external actions, and privacy acceptance tests.

### `docs/model-support.md`

The inference contract. It defines Ollama as the MVP backend, provider-neutral interfaces, model roles and profiles, hardware assumptions, memory safeguards, streaming and cancellation, setup behavior, failure recovery, and the future bundled-backend boundary.

### `docs/beta-metrics.md`

The validation contract. It defines product success metrics, retrieval and citation quality metrics, latency and reliability targets, resource limits, privacy checks, beta instrumentation rules, and release gates. Metrics are measurable without requiring cloud analytics.

## Consistency rules

- The MVP documents are normative for the first shippable release.
- `PRD.md` is normative for product intent and scope.
- The architecture, privacy, and model-support documents are normative for implementation constraints.
- The post-MVP plan is informative roadmap material unless a later approved requirements change promotes an item into MVP scope.
- When documents conflict, the canonical docs index records the resolution; implementation plans must be updated rather than overriding canonical requirements.
- Every linked Markdown document must exist, and links must be relative so the set remains portable.

## Acceptance criteria

- A fresh reader can navigate from `docs/README.md` to product intent, architecture, privacy, model behavior, MVP execution, and beta validation.
- All Markdown paths referenced by the plans exist or are replaced with links to the canonical documents.
- MVP and post-MVP boundaries are explicit.
- The documentation contains no unresolved placeholders or references to unavailable project context.
- A link/reference audit and a placeholder scan pass after editing.
