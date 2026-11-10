# Wayfinder tracker (local markdown)

No hosted tracker is configured for this repository, so the map and its tickets
live here, in git. Git history is the audit trail.

- **Map** (the canonical artifact): [`map.md`](map.md), labelled
  `wayfinder:map`.
- **Tickets**: `tickets/NNN-slug.md`. The number in the file name is the id;
  ids are never reused.
- Refer to a ticket by its **title**, not its id. A wall of ids is illegible.

## Ticket front matter

```yaml
---
id: 003
title: Land the decode registry and the JPEG backend
labels: [wayfinder:task]      # research | prototype | grilling | task
status: open                  # open | closed
assignee:                     # empty = unclaimed
blocked_by: [001, 002]        # ids that must be closed first
---
```

A **slice** is one commit-sized increment that leaves the tree building and
tested. This effort carries execution into the map, so a ticket is either a
slice or the decision that has to be settled immediately before one.

## Operations

- **Claim**: set `assignee` *before* any work, and commit that. An open
  ticket with an empty `assignee` is unclaimed.
- **Block**: list blocker ids in `blocked_by`; a ticket is unblocked when all
  of them are `closed`. There is no native dependency graph here, so this
  body convention stands in for one.
- **Frontier**: the open, unassigned, unblocked tickets — what is takeable now:

      wayfinder/frontier.sh

- **Create**: take the next free `NNN`, then wire `blocked_by` in a second
  pass; an id has to exist before another ticket can reference it.
- **Resolve**: append a `## Answer` section to the ticket, set
  `status: closed`, and add a one-line pointer to the map's *Decisions so
  far*.
