# Apple Books Connector

## Setup

Use one controlled book/library item with a unique title, author, and available
library metadata. Grant required access, connect, and sync.

## Prompts

| Prompt | Pass condition |
| --- | --- |
| `Who wrote the controlled title?` | Correct author with book citation. |
| `Which title has the unique author?` | Correct title and provenance. |
| `What library item matches the unique marker?` | Correct available metadata only. |

If the local library is absent, report the connector as empty or not tested;
do not invent library data.
