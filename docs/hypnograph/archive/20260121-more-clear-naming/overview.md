# More Clear Naming (Overview)

This project captures a naming cleanup aimed at making the core “hypnograph/hypnogram/layer/media” model easier to reason about.

**Status:** Complete (2026-01-22)

Primary reference: `docs/ontology/HypnographDomainDiagram.md`. Supporting data: `docs/ontology/types.json` / `docs/ontology/naming.json`.

## Current structure (today)

- `HypnoCore.HypnogramRecipe` contains `clips: [HypnoCore.HypnogramClip]`
- Each `HypnoCore.HypnogramClip` contains `sources: [HypnoCore.HypnogramSource]`
- Each `HypnoCore.HypnogramSource` contains `clip: HypnoCore.VideoClip` (a media slice) + transforms/blend/effects

## Target vocabulary (ideal-state nouns)

This is the “memorable schema”, mapped onto the current shapes:

| Current type | Ideal noun | Meaning |
|---|---|---|
| `HypnoCore.HypnogramRecipe` | `HypnographSession` | session/container of playable items |
| `HypnoCore.HypnogramClip` | `Hypnogram` | one playable item |
| `HypnoCore.HypnogramSource` | `HypnogramLayer` | one layer inside a playable item |
| `HypnoCore.VideoClip` | `MediaClip` | media slice backing a layer |

## Guiding rules

- No internal “compatibility aliases”: we don’t carry `typealias Old = New` long-term inside the codebase.
- Renames are end-to-end: update type names *and* related identifiers (variables, properties, method names, filenames where appropriate) so call sites don’t read like `let recipe = HypnographSession`.
- We can defer changing on-disk file keys (`.hypno`, settings, history) until the final step, after the new names are working end-to-end.
- At the final step, we can decide whether to:
  - do a one-time migration (recommended if there’s existing data), or
  - break compatibility and require users to re-save/recreate (acceptable if low cost).

## Next doc

See [Implementation Plan](implementation-plan.md) for a concrete step-by-step plan.

Shorthand for locals once renamed: `session` / `hypnogram` / `layer` / `mediaClip`.
