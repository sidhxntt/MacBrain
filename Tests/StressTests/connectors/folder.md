# Folder Connector

## Setup

Connect a controlled folder with one top-level text file, nested text file,
hidden file, PDF, unsupported file, and a file reserved for edit/delete tests.

## Prompts

| Prompt | Pass condition |
| --- | --- |
| `What is the exact marker?` | Finds the exact controlled value and opens the correct file citation. |
| `What is in the nested plan?` | Retrieves nested content, not only top-level files. |
| `What region is configured?` | Retrieves the hidden-file fixture without volunteering unrelated values. |
| `What changed most recently?` | After edit and sync, returns the new value only. |
| `What was the deleted marker?` | After deletion and sync, says local evidence does not establish it. |

The unsupported file and excluded dependency/build directories must not appear
as evidence.
