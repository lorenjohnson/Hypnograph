# Add Global Source Framing Setting: Implementation Planning

**Created**: 2025-01-16  
**Status**: Draft

This project introduces one new global preference and threads it through preview/live/render.

## Phase 0: Data model + persistence

Goal: represent Source Framing as a global setting in `hypnograph-settings.json`.

- Add enum: `SourceFraming` with cases:
  - `fill` (crop to cover frame)
  - `fit` (show whole source inside frame; unused area transparent)
- Add setting:
  - `Settings.sourceFraming` (default `fill`)

Notes:
- This is intentionally not per-clip and not per-source.
- Existing recipes remain unchanged.

## Phase 1: UI

Goal: expose the setting in Player Settings.

- Add a simple toggle or picker:
  - “Source Framing: Fill / Fit”
- Keep Output Aspect Ratio UI unchanged.

## Phase 2: Preview + live rendering behavior

Goal: have preview and live use the same global source framing behavior.

Implementation direction:
- In the compositor stage where each layer is scaled into the output frame:
  - `fill` uses aspect-fill
  - `fit` uses aspect-fit and centers the source
- Ensure aspect-fit pads with transparent pixels (so lower layers show through).

This should apply consistently for:
- video sources
- still image sources

## Phase 3: Export / render behavior

Goal: exported movies and snapshots match preview framing.

- Apply the same source framing rule in the render pipeline for:
  - AVFoundation compositing path
  - still-image snapshot/export paths

## Phase 4: Clean up and remove legacy terms

- Ensure no leftover “Fit in Window” wording exists in UI, HUD, docs, or code.
- Keep naming aligned with the product: “Source Framing” and “Output Aspect Ratio”.

