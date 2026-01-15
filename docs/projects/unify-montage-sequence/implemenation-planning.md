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

## Phase 2: Upgrade Recipe format to multi-clip (basic backward compatibility)

Goal: move to a single canonical recipe/document format that can represent 1+ clips.
Single-clip hypnograms become “a recipe with one clip”.

Why before history UI: clip history/navigation is fundamentally “a list of clips + current index”.
If the end-state recipe format already contains `[Clip]`, it’s cheaper to build on top of that
than to create a parallel history structure and refactor later.

Minimum data model direction:

- `HypnogramRecipe` becomes the multi-clip container (`clips: [HypnogramClip]` + metadata).
- `HypnogramClip` holds what today lives on `HypnogramRecipe` (sources/layers, duration, playRate, effect chains).
- Runtime state should hold one `HypnogramRecipe` plus a `currentClipIndex` (not a parallel history structure).

Backward compatibility (minimal):
- When decoding, if there is no top-level `clips` key, decode the legacy single-clip fields and wrap them into `clips: [legacyClip]`.

Notes:
- This phase is mostly data-shape + migration, but it will necessarily touch state and UI bindings where they assumed a single clip.
- Keep the UX “preview == render”: preview is always the currently selected clip (`currentClipIndex`) in the materialized list.

Settings to add early:

- `historyLimit`: Int (default 200).
- `maxLayers`: Int (generation ceiling; new clips choose a layer count in `1...maxLayers`).
- `randomizeBlendModes`: Bool.
- `randomizeGlobalEffect`: Bool (random from all templates; OFF = carry forward prior clip global chain).
- `clipLengthMin/Max`: Double (default 2–15).
- `watchMode`: Bool (preview behavior; ON = advance/generate on clip end, OFF = loop current clip).

## Phase 3: Playback semantics (replace Watch timer)

Goal: remove the watch timer and make playback event-driven.

Hard requirement:
- if `watchMode` is ON, advance on clip end; if at end of the clip list, generate and append next (dropping oldest if beyond `historyLimit`).
- if `watchMode` is OFF, loop the current clip (do not auto-generate).

Implementation approach:

1) **Player-driven end callback**:
   - the preview player emits “clip ended” at the end of the current clip
   - Dream advances `currentClipIndex` (or generates next if at end)
   - remove the current “loop-on-end” behavior from preview when `watchMode` is ON

Note: any “how many clips to render” knob belongs to render/export only (e.g. `renderClipCount`).

## Phase 4: Clip History UX (navigate/edit/delete)

Goal: implement the new primary behavior: ordered, materialized clip history you can navigate/edit/delete.

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

Notes:
- This phase should primarily be UI/commands + small state glue; the clip list + index should already exist from Phase 2.

## Phase 5: Render clip tape (minimal UI)

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
