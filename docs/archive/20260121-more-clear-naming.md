---
doc-status: done
---

# More Clear Naming

This project captures a naming cleanup aimed at making the core "hypnograph/hypnogram/layer/media" model easier to reason about.

Primary reference: `docs/ontology/HypnographDomainDiagram.md`. Supporting data: `docs/ontology/types.json` / `docs/ontology/naming.json`.

## Overview

### Current structure (today)

- `HypnoCore.HypnogramRecipe` contains `clips: [HypnoCore.HypnogramClip]`
- Each `HypnoCore.HypnogramClip` contains `sources: [HypnoCore.HypnogramSource]`
- Each `HypnoCore.HypnogramSource` contains `clip: HypnoCore.VideoClip` (a media slice) + transforms/blend/effects

### Target vocabulary (ideal-state nouns)

This is the "memorable schema", mapped onto the current shapes:

| Current type | Ideal noun | Meaning |
|---|---|---|
| `HypnoCore.HypnogramRecipe` | `HypnographSession` | session/container of playable items |
| `HypnoCore.HypnogramClip` | `Hypnogram` | one playable item |
| `HypnoCore.HypnogramSource` | `HypnogramLayer` | one layer inside a playable item |
| `HypnoCore.VideoClip` | `MediaClip` | media slice backing a layer |

---

## Implementation Plan

Goal: align types and terminology with the "ideal-state nouns" from the overview.

Constraint: keep changes mechanical and rename-safe; avoid adding long-lived aliases. Defer on-disk key changes until the final step.

### Cross-cutting rule: rename identifiers, not just types

For each rename, also update:

- Local variables and parameters (avoid `let recipe = HypnographSession`, prefer `session`).
- Property names and computed properties where they encode the old noun.
- Function names (`loadRecipe` → `loadSession`, etc.) when the noun is part of the API.
- File names when they are user-facing or central (optional, but preferred for core models).

Suggested identifier mapping (use consistently across the codebase):

| Type rename | Preferred variable/parameter name |
|---|---|
| `HypnogramRecipe` → `HypnographSession` | `recipe` → `session` |
| `HypnogramClip` → `Hypnogram` | `clip` → `hypnogram` |
| `HypnogramSource` → `HypnogramLayer` | `source` → `layer` |
| `VideoClip` → `MediaClip` | `clip`/`videoClip` → `mediaClip` |

### Guiding rules

- No internal "compatibility aliases": we don't carry `typealias Old = New` long-term inside the codebase.
- Renames are end-to-end: update type names *and* related identifiers (variables, properties, method names, filenames where appropriate) so call sites don't read like `let recipe = HypnographSession`.
- We can defer changing on-disk file keys (`.hypno`, settings, history) until the final step, after the new names are working end-to-end.
- At the final step, we can decide whether to:
  - do a one-time migration (recommended if there's existing data), or
  - break compatibility and require users to re-save/recreate (acceptable if low cost).

---

## Phase 0: Inventory and diagram refresh

- Update `docs/ontology/HypnographDomainDiagram.md` labels to match the chosen final nouns.
- List all call sites / file formats that store:
  - `HypnogramRecipe`
  - `HypnogramClip`
  - `HypnogramSource`
  - `VideoClip`

## Phase 1: Media slice naming

- Rename `VideoClip` → `MediaClip`.
  - Update all references (`HypnogramSource.clip`, libraries, tests, UI).
  - Keep JSON keys unchanged for now (still encode/decode as `clip` if that is the existing key).

## Phase 2: Layer naming

- Rename `HypnogramSource` → `HypnogramLayer`.
  - Update references such as `clip.sources` → `clip.layers` only if/when we also change keys and API shape; otherwise keep property names stable until Phase 4.

## Phase 3: Playable item naming

- Rename `HypnogramClip` → `Hypnogram`.
  - Update container properties (`recipe.clips` → `session.hypnograms`) only in Phase 4 (to avoid partial schema mismatches).

## Phase 4: Session naming + schema/key finalization (breaking point)

This is the "final step": once everything works, then flip persisted names/keys together.

- Rename `HypnogramRecipe` → `HypnographSession`.
- Sweep identifier names: `recipe` → `session` across app/UI/storage layers.
- Update persisted keys everywhere (files, settings, history), likely:
  - `clips` → `hypnograms`
  - `sources` → `layers`
  - `clip` → `mediaClip`
- Decide migration strategy:
  - **Option A (migration)**: support decoding old keys once, re-save in new schema, then remove legacy support later.
  - **Option B (break)**: no migration; existing `.hypno` and history are considered invalid and must be recreated.

## Phase 5: Cleanup

- Remove any temporary bridging code if used during migration.
- Ensure docs match the final nouns (`docs/ontology/*` and project docs).

---

Shorthand for locals once renamed: `session` / `hypnogram` / `layer` / `mediaClip`.
