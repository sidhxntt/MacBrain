# Browser Profiles Connector

## Setup

In a controlled browser profile, create a unique bookmark, history item,
reading-list item, download, and open tab. Connect that profile and sync.

## Prompts

| Prompt | Pass condition |
| --- | --- |
| `What page did I save for later?` | Correct bookmark or reading-list title and URL citation. |
| `Which page did I recently visit with the unique title?` | Correct history item, not a bookmark. |
| `What did I download with the unique name?` | Correct download evidence. |
| `What is open in the controlled browser?` | Correct open-tab data where the browser exposes it. |

Disconnect the profile and confirm that its browser evidence is no longer
returned.
