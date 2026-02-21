---
created: 2026-02-17
updated: 2026-02-17
status: active
---

# Sets Model Direction

## Overview

This document captures forward-looking model design for Sets.

It is intentionally decoupled from rollback execution. Current implementation work should follow:

- `sets-reset-and-modeling-plan.md` for reset/removal
- this doc for post-reset architecture and UX planning

## Working Terminology

- Use **Set** as the general concept.
- Treat **History** as one special set.
- Treat **Favorites** as one special set.
- Allow user-created ad hoc sets.

## Model Direction

Proposed core entities:

- `SetID`
- `ClipSet`:
  - `id`
  - `name`
  - `clips: [Hypnogram]` (independent payload, not references into history IDs)
  - metadata (`createdAt`, `updatedAt`, optional tags)
- `SetStore`:
  - collection of sets
  - active set selection
  - persistence

Important: avoid coupling set membership to history clip IDs.

## Playback Contract

Single playback contract regardless of active set:

- `next` / `previous` navigate inside active set.
- If at end:
  - in auto-advance mode: generate/append a new clip to active set.
  - in loop mode: wrap to the first clip in active set.
- If active set is empty: create first clip.

This keeps behavior consistent whether active set is History, Favorites, or custom.

## UX Direction

- Left sidebar gets a Set browser tab.
- Switching sets should be fluid and low-friction.
- Adding current clip to another set should be one action from player, menus, or context menu.
- Keep player bar simple and mode-obvious (transport + mode + save/render).

## Open Questions

- Copy-on-add vs shared clip identity across sets.
- How to represent “current clip” when switching active sets.
- Whether History should be immutable provenance or fully editable like other sets.
- Save/load semantics for multi-clip sessions once sets exist.
- How Favorites maps into SetStore migration without data loss.

## Proposed Next Design Step

Before implementation, write a small `sets-contract.md` that defines:

- state machine and transitions
- invariants and edge cases
- persistence boundaries
- command/menu/player-bar behavior by state
