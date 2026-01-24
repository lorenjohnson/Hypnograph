---
last_reviewed: 2026-01-18T00:00:00Z
---

# Recipe and Hypnogram Persistence Architecture

## Scope
This document covers recipe data structures, save/load flows, and persistent
storage for hypnograms.

## Sources
- `HypnoCore/Recipes/HypnogramRecipe.swift`
- `HypnoCore/Recipes/HypnogramSource.swift`
- `Hypnograph/RecipeStore.swift`
- `Hypnograph/RecipeFileActions.swift`
- `Hypnograph/HypnogramStore.swift`
- `Hypnograph/EffectChainLibraryActions.swift`

## Core Data Model

### HypnogramRecipe
- The single source of truth for a composition.
- Contains:
  - ordered `sources` (array of `HypnogramSource`)
  - `targetDuration`
  - `playRate`
  - global `effectChain`
  - `createdAt`
  - optional `snapshot` (base64 JPEG)

### HypnogramSource
- A source clip with user transforms, blend mode, and per-source effect chain.

### VideoClip and MediaFile
- `VideoClip` is a slice of a `MediaFile` with `startTime` and `duration`.
- `MediaFile` abstracts over URLs and Photos identifiers.

## File Format
- Preferred extension: `.hypno` (legacy `.hypnogram` is supported).
- File contents are JSON, not a binary PNG.
- The recipe embeds a base64 JPEG snapshot at 1080p for previews.
- JSONC-style comments are supported on load (comment lines are stripped).

## Save Flow
1. Dream captures a snapshot as `CGImage`.
2. `RecipeStore.save()` embeds the JPEG snapshot into the recipe and writes JSON.
3. `HypnogramStore.add()` records metadata in `hypnogram-store.json` and
   stores a small thumbnail preview for list views.

## Load Flow
- `RecipeStore.load()` decodes JSON into `HypnogramRecipe`.
- `RecipeFileActions.openRecipe()` provides the Open Panel UI.
- `EffectChainLibraryActions` can extract effect chains used in a recipe and
  merge/replace the current effects library.

## HypnogramStore
- Stores a list of saved entries.
- File location: `~/Library/Application Support/Hypnograph/hypnogram-store.json`.
- Each entry tracks `recipeURL`, name, date, and optional thumbnail.

## Export Isolation
- `HypnogramRecipe.copyForExport()` deep-copies effect chains for export.
- Export rendering uses `EffectManager.forExport(recipe:)` to avoid state bleed
  from preview or live playback.
