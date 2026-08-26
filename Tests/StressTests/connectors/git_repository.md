# Git Repository Connector

## Setup

Create a controlled repository with a branch, commit, author, changed file, and
unique text marker. Connect the repository and sync.

## Prompts

| Prompt | Pass condition |
| --- | --- |
| `Which branch contains the unique marker?` | Correct branch and repository citation. |
| `Who authored the change to the controlled file?` | Correct commit author and file evidence. |
| `What changed in the controlled commit?` | Grounded summary of available commit/file data. |
| `What is the most recent controlled commit?` | Correct commit ordering and provenance. |

Repository facts must not be used as evidence for unrelated Mail, Calendar, or
folder questions.
