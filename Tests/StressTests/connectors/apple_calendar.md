# Apple Calendar Connector

## Setup

Create a controlled event with a unique title, date/time, attendee, location,
and note. Authorize Calendar, connect, and sync.

## Prompts

| Prompt | Pass condition |
| --- | --- |
| `What is the title and date of the scheduled item?` | Exact event title and date with citation. |
| `Who is attending the event at the unique location?` | Exact attendee evidence; no invented attendees. |
| `What does the event note say?` | Bounded summary or exact supported content with citation. |
| `When is the next controlled event?` | Correct ordering by date/time. |

Edit the event and sync; the old title/date must not persist in a later answer.
