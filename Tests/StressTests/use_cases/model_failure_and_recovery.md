# Model Failure and Recovery

| Action | Pass condition |
| --- | --- |
| Stop the local model service and send a non-source question. | Clear, bounded failure; the app does not hang. |
| Restore the service and retry. | The same prompt completes without a duplicate user message. |
| Start a source-backed answer and choose Stop. | Useful verified evidence remains visible. |
| Retry the stopped source-backed answer. | Complete answer is grounded and cited, with no stale uncited content. |
| Repeat a live-system question after state changes. | It is evaluated freshly, not served from response cache. |
