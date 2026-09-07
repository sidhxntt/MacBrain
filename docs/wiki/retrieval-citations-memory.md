# Retrieval, Citations, and Memory

## Evidence pipeline

`HybridEvidenceRetriever` accepts an authorized query scope and combines FTS5 and vector candidates. It normalizes scores, removes duplicate/adjacent chunks, promotes source diversity and recency, optionally expands a lightweight graph, and passes only a bounded set through `EvidenceAcceptancePolicy`. `ContextAssembler` adds selected conversation turns and explicit live context without exceeding the configured model budget.

Each `RetrievalEvidence` preserves a stable citation ID, source title/type/location/date, excerpt, offset/page and score. `CitationValidator` ensures a rendered citation maps to a real accepted excerpt. Search-only mode stops here and returns the evidence directly; generation is not required to inspect local knowledge.

## Grounded generation

`OllamaProvider` receives structured instructions, the question, bounded evidence and authorized context—not an unbounded database dump. `StreamingChatResponder` sends partial deltas to the chat store, supports stop/retry, and keeps failure separate from a completed answer. The prompt contract distinguishes quoted evidence from inference and requires explicit uncertainty for missing or conflicting support. Source cards appear with the answer and can open the native origin.

## Memories are not evidence

`LocalMemoryRepository` and `MemoryStore` hold assistant-created, explicitly managed durable information. A user can save, inspect, edit, export, delete, or forget memories. Indexed source content and memories are different record categories with different UI and retrieval semantics: a memory may guide a response but must not masquerade as a cited document. Forgetting removes it from memory retrieval; deleting a source removes it from evidence retrieval.
