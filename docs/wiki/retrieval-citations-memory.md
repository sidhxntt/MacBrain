# Retrieval, citations, and memory

## Evidence pipeline

`HybridEvidenceRetriever` accepts an authorized query scope and combines lexical and semantic candidates. It can fall back to lexical search, removes duplicates/near-adjacent repeats, favors diversity and recency, performs bounded graph expansion where available, and passes candidates to `EvidenceAcceptancePolicy`. `ContextAttachment` and eligible conversation turns are added only within the prompt budget.

Every `RetrievalEvidence` carries a stable citation identifier plus title, source type, location, date, excerpt, score, and available offset/page metadata. `CitationValidator` requires a rendered reference to resolve to accepted evidence. Search-only stops at this point: a user can inspect local evidence without asking a model to summarize it.

## Grounded generation

`StreamingChatResponder` gives the local provider structured instructions, a question, bounded evidence, and authorized context—not a database dump. It streams deltas, supports cancellation/retry, and keeps a generation failure distinct from a completed response. The prompt asks the model to mark missing/conflicting support as uncertainty, while the UI displays citation cards beside the answer.

This is evidence-aware generation, not proof that every generated sentence is correct. Source cards and opening the original material remain the final audit path.

## Memories are not evidence

`LocalMemoryRepository` and `MemoryStore` represent explicit, durable user-managed information. Users can inspect, edit, export, delete, or forget it. Memory records and indexed source records use different models and UI semantics: a memory may provide helpful continuity, but it cannot masquerade as a cited document. Removing a source removes its evidence eligibility; forgetting a memory removes it from memory use.
