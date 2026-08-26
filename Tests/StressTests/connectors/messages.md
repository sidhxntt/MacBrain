# Messages Connector

## Setup

Use a controlled conversation with a unique participant, phrase, and time.
Grant any required Full Disk Access, connect, and sync.

## Prompts

| Prompt | Pass condition |
| --- | --- |
| `Who said the unique phrase, and when?` | Correct participant and timestamp with message citation. |
| `What did the conversation decide?` | Only explicit message evidence; no inferred commitment. |
| `Which conversation mentioned the unique marker?` | Correct conversation provenance. |

If access is denied, the connector must remain recoverable and return no
indexed message content.
