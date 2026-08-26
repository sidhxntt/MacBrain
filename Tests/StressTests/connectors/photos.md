# Photos Connector

## Setup

Use one controlled Photos item with unique title or metadata, date, and
album/collection where available. Grant Photos permission, connect, and sync.

## Prompts

| Prompt | Pass condition |
| --- | --- |
| `What is the title of the item in the controlled collection?` | Correct metadata with citation. |
| `When was the controlled item created?` | Correct available date metadata. |
| `Which collection contains the unique item?` | Correct album/collection provenance. |

Only metadata should be used; the app must not claim it accessed original media
content when the connector supports metadata only.
