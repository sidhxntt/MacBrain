# Apple Reminders Connector

## Setup

Create a controlled reminder with unique title, due date, list, priority, and
note. Authorize Reminders, connect, and sync.

## Prompts

| Prompt | Pass condition |
| --- | --- |
| `What is the deadline and priority of the pending task?` | Correct reminder facts and citation. |
| `Which list contains the unique task?` | Correct list; no substitution from Calendar. |
| `What note is attached to the pending task?` | Correct note evidence. |
| `What task is due first?` | Correct date ordering among controlled reminders. |

Complete, edit, or delete the fixture, sync, and verify that the resulting
answer reflects its current state.
