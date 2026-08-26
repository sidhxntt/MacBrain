# Apple Mail Connector

## Setup

Use a controlled message with a unique subject, sender, recipient, date,
attachment name, and body phrase. Authorize Mail, connect, and sync.

## Prompts

| Prompt | Pass condition |
| --- | --- |
| `Who sent the message about the unique subject?` | Correct sender and message citation. |
| `When was the message about the attachment sent?` | Correct timestamp and attachment provenance. |
| `What did the message ask for?` | Returns only explicit body evidence. |
| `Which message mentioned the unique phrase?` | Opens the exact controlled message. |

Decline permission once: the source must report a recoverable permission state
and index no message content.
