# Freshness and Deletion

| Setup action | Prompt | Pass condition |
| --- | --- | --- |
| Add a uniquely marked source and sync. | `What is the newest marker?` | Finds and cites the new value. |
| Change the marker and sync. | `What is the newest marker?` | Returns only the new value. |
| Delete the marker and sync. | `What is the newest marker?` | Says evidence does not establish it. |
| Disconnect and remove a source. | Repeat its retrieval prompt. | No removed data appears. |
| Change safe live system state. | `What is available storage right now?` | Uses fresh live state, not a cache. |

Any old value or deleted citation is a failure.
