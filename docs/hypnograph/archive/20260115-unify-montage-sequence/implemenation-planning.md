# Unify Montage/Sequence: Implementation Planning

**Created**: 2026-01-15  
**Status**: Completed

This is an implementation-oriented plan derived from `docs/_archive/projects/unify-montage-sequence/overview.md`.

## Guiding constraints

- Delete “Sequence mode” as a user-facing concept early.
- Preserve the “preview == render” guarantee by rendering only materialized clips.
- Keep the app usable as an “open-and-watch” infinite machine with minimal UI.
- Prefer incremental refactors that keep the app runnable at each step.

## Phase 0: Rename + unconfuse (cheap wins)

Goal: align names to the new model without changing behavior yet.

**Status**: Completed

- Rename “Max Sources” to **Max Layers** in UI and types.
  - `PlayerConfiguration.maxSourcesForNew` → `maxLayers` (with Codable migration).
- Rename “Duration” to **Clip Length (min/max)** in UI.
  - Introduce `clipLengthMinSeconds` / `clipLengthMaxSeconds` (default 2–15).
  - Keep existing `recipe.targetDuration` temporarily as “current clip length” until clip history exists.
- Clarify blend defaults:
  - default blend = SourceOver for base layer; Screen for other layers.

Why early: it makes later PRs readable and reduces mode-shaped thinking.

## Phase 1: Remove Sequence Mode (UI + state)

Goal: collapse mode branching so there is only one preview composition path.

**Status**: Completed

Work items:

- Remove mode toggles in Player Settings (Montage/Sequence/Live → Preview/Live).
- Remove `DreamMode` branching and sequence deck state where possible:
  - one active preview player/view (montage-like, layered)
  - remove/retire `SequencePlayerView` usage
- Keep Live as a target, not a mode.

Notes:
- This phase can keep the existing `HypnogramRecipe` shape to avoid a huge data migration.
- Sequence-specific export behavior is removed; export becomes “export what you’re previewing” until clip-history export exists.

## Phase 1.5: Remove sequence render path (renderer + tests)

Goal: eliminate the “sources-as-timeline” interpretation in the renderer so the codebase
only supports “sources-as-layers” (montage) until clip-history export exists.

**Status**: Completed

- Remove `RenderEngine.Timeline` / `CompositionBuilder.TimelineStrategy` / `buildSequence(...)`.
- Remove any sequence-oriented renderer tests.

## Phase 2: Upgrade Recipe format to multi-clip (basic backward compatibility)

Goal: move to a single canonical recipe/document format that can represent 1+ clips.
Single-clip hypnograms become “a recipe with one clip”.

**Status**: Completed (`64cf855`)

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

Goal: remove the watch timer (if any remains) and make playback event-driven.

**Status**: Completed (`71e2430`)

Hard requirement:
- if `watchMode` is ON, advance on clip end; if at end of the clip list, generate and append next (dropping oldest if beyond `historyLimit`).
- if `watchMode` is OFF, loop the current clip (do not auto-generate).

Implementation approach:

1) **Player-driven end callback**:
   - the preview player emits “clip ended” at the end of the current clip
   - Dream advances `currentClipIndex` (or generates next if at end)
   - remove the current “loop-on-end” behavior from preview when `watchMode` is ON

Notes:
- We do **not** preserve the old “user interaction prolongs clip” behavior.
- Implemented by removing the watch timer entirely and advancing via `AVPlayerItemDidPlayToEndTime`.
- Naming: `watch` → `watchMode` in settings (decode legacy `watch` for backward compatibility).

Note: any “how many clips to render” knob belongs to render/export only (e.g. `renderClipCount`).

## Phase 4: Clip History UX (navigate/edit/delete)

Goal: implement the new primary behavior: ordered, materialized clip history you can navigate/edit/delete.

**Status**: Completed

User-facing behaviors to implement:

- Generate and append new clips; drop oldest if beyond `historyLimit`.
- If `watchMode` is ON and you are “back in history” (i.e. there are future clips after the current index), auto-advance continues through those existing clips; only at the end does it generate/append a new clip.
- Navigate previous/next clip.
  - Keyboard: Left Arrow = previous clip, Right Arrow = next clip.
  - If there is no “future” clip (at end of history), Right Arrow does nothing.
  - If there is a prior clip, Left Arrow jumps immediately to that clip.
  - HUD: when the user manually navigates history (arrow keys or menu commands), flash a clip counter overlay in the same size/style as the existing Layer counter, but in blue (e.g. `3/57`).
- Edit overwrites the current clip in place.
- Delete current clip.
- “Clear Clip History” menu item keeps the current clip and deletes all history before/after it.
- “Load recipe file” appends the loaded clip(s) into history (does not wipe/replace history).
  - For now, `.hypno` load is “one clip”, so it appends one clip and jumps to it.
  - Later, when multi-clip recipes exist, load should append all clips and reset selection state (see Phase 5).

Notes:
- This phase should primarily be UI/commands + small state glue; the clip list + index should already exist from Phase 2.
- `historyLimit` changes: on load/save, trim oldest to limit and adjust `currentClipIndex` accordingly.
## Out of scope: Sequence saving / export ranges

Saving/rendering a range of clips from history is intentionally **out of scope** for this project.
It is tracked as a separate project:
`docs/Hypnograph/projects/20250116-save-sequences/overview.md`

## What else to do early (high leverage)

- Add “Delete Clip” and “Clear Clip History” commands to the left menu early; these will be used constantly during iteration.
- Stabilize identity: give each clip a stable id so edits/deletes don’t cause weird UI state.
  - Implemented as `HypnogramClip.id`.
- Persist history separately from preferences so `hypnograph-settings.json` stays clean (e.g., `clip-history.json`).
  - Phase 2 moved us to `recipe.clips`, which will grow once we persist history; avoid persisting large recipe blobs inside `hypnograph-settings.json` (use `clip-history.json` instead).
  - `hypnograph-settings.json` (preferences-only): `watchMode`, `historyLimit`, `clipLengthMinSeconds`, `clipLengthMaxSeconds`, `outputFolder`, `snapshotsFolder`, `sources`, `activeLibraries`, `sourceMediaTypes`, `outputResolution`, `playerConfig.aspectRatio`, `playerConfig.playerResolution`, `playerConfig.maxLayers`, `effectsListCollapsed`, `previewAudioDeviceUID`, `previewVolume`, `liveAudioDeviceUID`, `liveVolume`.
  - history file (state): `clips`, `currentClipIndex` (and later in/out points).
  - Corruption handling: if history file fails to decode, rename it to something like `clip-history.corrupt-<timestamp>.json` and start a new history.
- Ensure Effects window scopes to “current clip + selected layer/global” as the history index changes (avoid accidental edits to the wrong clip).
- Consider flattening `Settings.playerConfig` if it reduces type/JSON complexity now that `lastRecipe` is removed (optional cleanup).
