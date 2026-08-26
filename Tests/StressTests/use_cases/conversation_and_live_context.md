# Conversation and Live Context

| Setup / prompt | Pass condition |
| --- | --- |
| Ask a source-backed question, then: `Which source proves that?` | Retains relevant conversational provenance. |
| Start a new chat and ask an unrelated question. | Does not leak the previous chat's content. |
| Add a unique clipboard phrase, then: `Repeat the phrase I just provided.` | Visible chip and exact one-turn result. |
| Without adding it again: `Repeat that phrase again.` | Does not reuse expired context or cached response. |
| Add then remove a live-context chip. | Removed content is absent from the reply. |

Repository context must never become evidence for an unrelated source-backed
answer.
