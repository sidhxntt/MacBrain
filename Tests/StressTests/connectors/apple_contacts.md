# Apple Contacts Connector

## Setup

Create a controlled contact with a unique display name, organization, email,
and phone number. Authorize Contacts, connect, and sync.

## Prompts

| Prompt | Pass condition |
| --- | --- |
| `What organization is the named person associated with?` | Correct organization and contact citation. |
| `Which email belongs to the controlled contact?` | Exact controlled email only. |
| `What phone number is stored for the named person?` | Exact controlled number only. |
| `What information is not established for this person?` | Does not infer missing personal details. |

Verify that a denied Contacts permission produces no indexed contact result.
