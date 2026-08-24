# Notch Brain Beta Metrics and Release Gates

Metrics are collected locally or from opt-in exported test reports. No personal content is required for measurement; fixtures and redacted metadata are preferred.

## Core success

The beta passes its product test when a clean-machine user can open the sidebar, ask about a seeded local decision, receive a concise cited answer, open the exact source, ask a follow-up, save a memory, forget it, and confirm that no data left the machine.

## Quality targets

- At least 90% of seeded answerable questions include the correct supporting source.
- At least 95% of rendered citations open the exact source and location represented by the citation.
- Unsupported or conflicting fixture questions produce an uncertainty response rather than an invented fact in at least 95% of runs.
- Incremental indexing does not duplicate unchanged documents or retain deleted fixture sources.

## Responsiveness and reliability

- Sidebar activation feels immediate and does not block on indexing or model startup.
- Search returns initial evidence before or alongside generation whenever the provider is available.
- Cancellation stops visible generation and leaves a recoverable conversation state.
- Clean-machine setup, migration, restart recovery, permission denial, provider outage, malformed files, and interrupted indexing each have a passing acceptance case.
- No reproducible data-loss, silent-indexing, or cross-source authorization defect remains open.

## Resource targets

- Indexing remains responsive during normal foreground use.
- Context assembly stays within the selected model’s configured budget.
- The app surfaces memory pressure and provides a smaller-model or search-only fallback.
- Indexing and generation do not produce unbounded queues or retain cancelled request content.

## Privacy gates

Release is blocked if a default flow sends content to a hosted service, indexes an unselected root, includes an excluded file, logs source content, or performs a mutating action without confirmation. Deletion and forget flows must be verified by querying after removal.

## Beta report

Each beta build records version, OS/hardware class, selected model profile, fixture result counts, latency buckets, error categories, and privacy-test results. Reports exclude source text, prompts, responses, paths, identifiers, and raw telemetry unless the user explicitly exports a diagnostic bundle.
