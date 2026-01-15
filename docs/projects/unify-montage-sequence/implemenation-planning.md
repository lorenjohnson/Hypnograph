# Unify Montage/Sequence: Implementation Planning

**Created**: 2026-01-15  
**Status**: Planning

This is an implementation-oriented plan derived from `docs/projects/unify-montage-sequence/overview.md`.

## Guiding constraints

- Delete “Sequence mode” as a user-facing concept early.
- Preserve the “preview == render” guarantee by rendering only materialized clips.
- Keep the app usable as an “open-and-watch” infinite machine with minimal UI.
- Prefer incremental refactors that keep the app runnable at each step.

## Phase 0: Rename + unconfuse (cheap wins)

Goal: align names to the new model without changing behavior yet.

- Rename “Max Sources” to **Max Layers** in UI and types.
  - `PlayerConfiguration.maxSourcesForNew` → `maxLayers` (with Codable migration).
- Rename “Duration” to **Clip Length (min/max)** in UI.
  - Introduce `clipLengthMinSeconds` / `clipLengthMaxSeconds` (default 2–15).
  - Keep existing `recipe.targetDuration` temporarily as “current clip length” until tape exists.
- Clarify blend defaults:
  - default blend = SourceOver for base layer; Screen for other layers.

Why early: it makes later PRs readable and reduces mode-shaped thinking.

## Phase 1: Remove Sequence Mode (UI + state)

Goal: collapse mode branching so there is only one preview composition path.

Work items:

- Remove mode toggles in Player Settings (Montage/Sequence/Live → Preview/Live).
- Remove `DreamMode` branching and sequence deck state where possible:
  - one active preview player/view (montage-like, layered)
  - remove/retire `SequencePlayerView` usage
- Keep Live as a target, not a mode.

Notes:
- This phase can keep the existing `HypnogramRecipe` shape to avoid a huge data migration.
- Sequence-specific export behavior is removed; export becomes “export what you’re previewing” until clip tape export exists.

## Phase 1.5: Remove sequence render path (renderer + tests)

Goal: eliminate the “sources-as-timeline” interpretation in the renderer so the codebase
only supports “sources-as-layers” (montage) until clip-tape export exists.

- Remove `RenderEngine.Timeline` / `CompositionBuilder.TimelineStrategy` / `buildSequence(...)`.
- Remove any sequence-oriented renderer tests.
- Keep `HypnogramRecipe.mode` as a legacy decode field if it exists in old `.hypno` files, but treat it as informational only.

## Phase 2: Introduce Clip History (materialized)

Goal: implement the new primary behavior: ordered clip history you can navigate/edit/delete.

Clarification: `HypnogramRecipe` stays a *single-clip* recipe (layers + effects + duration).
We do not introduce “recipes that contain sequences of clips”. When we render multiple clips,
that is represented as a separate export request/spec that references a slice of `ClipHistory`.

Minimum viable data model (can be refined later):

- `Clip` = a `HypnogramRecipe` plus any clip-level metadata needed (e.g., stable id, createdAt).
  - Per-clip `playRate` already exists on `HypnogramRecipe`.
  - Per-clip effects already exist (global + per-layer) on `HypnogramRecipe`.
- `ClipHistory` = `[Clip]` + `currentIndex` + `historyLimit`.

User-facing behaviors to implement:

- Generate and append new clips; drop oldest if beyond `historyLimit`.
- Navigate previous/next clip.
  - Keyboard: Left Arrow = previous clip, Right Arrow = next clip.
  - If there is no “future” clip (at end of history), Right Arrow does nothing.
  - If there is a prior clip, Left Arrow jumps immediately to that clip.
  - HUD: when the user manually navigates history (arrow keys or menu commands), flash a clip counter overlay in the same size/style as the existing Layer counter, but in blue (e.g. `3/57`).
- Edit overwrites the current clip in place.
- Delete current clip.
- “Clear Clip History” menu item keeps the current clip and deletes all history before/after it.

Settings to add early:

- `historyLimit`: Int (default 200).
- `maxLayers`: Int.
- `randomizeLayerCount`: Bool (generation behavior).
  - When ON, new clips choose `layerCount` randomly in `1...maxLayers`.
  - When OFF, new clips always start with `layerCount == maxLayers`.
- `randomizeBlendModes`: Bool.
- `randomizeGlobalEffect`: Bool (random from all templates; OFF = carry forward prior clip global chain).
- `clipLengthMin/Max`: Double (default 2–15).
- `watchMode`: Bool (preview behavior; ON = advance/generate on clip end, OFF = loop current clip).

## Phase 3: Playback semantics (replace Watch timer)

Goal: remove the watch timer and make playback event-driven.

Hard requirement:
- if `watchMode` is ON, advance on clip end; if at end of history, generate and append next.
- if `watchMode` is OFF, loop the current clip (do not auto-generate).

Implementation approach:

1) **Player-driven end callback**:
   - the preview player emits “clip ended” at the end of the current clip
   - Dream advances `ClipHistory.currentIndex` (or generates next if at end)
   - remove the current “loop-on-end” behavior from preview when `watchMode` is ON

Note: any “how many clips to render” knob belongs to render/export only (e.g. `renderClipCount`).

## Phase 4: Render clip tape (minimal UI)

Goal: export a concatenation of materialized clips (hard cuts), matching preview.

Minimal render UX:

- Ask for `renderClipCount` (N) each time (or remember last value).
- Default selection comes from history only:
  - If there are at least N clips starting at the current clip, render that forward slice.
  - Otherwise render the last N clips available (ending at the end of history).

Future (when we want one “recipe” type to cover both single-clip and multi-clip):
- Keep `HypnogramRecipe` as the clip recipe (layers + effects + duration).
- Introduce a higher-level “sequence”/“episode” document (e.g. `HypnogramSequence`) that stores `[HypnogramRecipe]` for export/persistence.

Render architecture direction:

- First pass can enqueue N renders and stitch, or build a single composition that concatenates clip compositions.
- Longer-term goal (not required in MVP): one “render tape” path that handles:
  - layering within each clip, and
  - concatenation across clips

## What else to do early (high leverage)

- Add “Delete Clip” and “Clear Clip History” commands to the left menu early; these will be used constantly during iteration.
- Stabilize identity: give each clip a stable id so edits/deletes don’t cause weird UI state.
- Persist tape separately from general settings if it keeps settings.json clean (e.g., `clip-tape.json`), but keep it simple initially.
- Ensure Effects window scopes to “current clip + selected layer/global” as the tape index changes (avoid accidental edits to the wrong clip).
