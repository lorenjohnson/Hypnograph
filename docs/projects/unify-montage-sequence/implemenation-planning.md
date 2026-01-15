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

## Phase 2: Introduce Clip Tape (materialized history) + maxClips

Goal: implement the new primary behavior: ordered clip history you can navigate/edit/delete.

Minimum viable data model (can be refined later):

- `Clip` = a `HypnogramRecipe` plus any clip-level metadata needed (e.g., stable id, createdAt).
  - Per-clip `playRate` already exists on `HypnogramRecipe`.
  - Per-clip effects already exist (global + per-layer) on `HypnogramRecipe`.
- `ClipTape` = `[Clip]` + `currentIndex` + `historyLimitK` + `clipCountSetting` (N or ∞).

User-facing behaviors to implement:

- Generate and append new clips; drop oldest if beyond `K`.
- Navigate previous/next clip.
  - Keyboard: Left Arrow = previous clip, Right Arrow = next clip.
  - If there is no “future” clip (at end of history), Right Arrow does nothing.
  - If there is a prior clip, Left Arrow jumps immediately to that clip.
- Edit overwrites the current clip in place.
- Delete current clip.
- “Clear Clip History” menu item (resets and generates a fresh clip).

Settings to add early:

- `clipCount`: `Int?` (nil = ∞) or an enum.
- `historyLimitK`: Int (default 200).
- `maxLayers`: Int.
- `randomizeLayerCount`: Bool.
- `randomizeBlendModes`: Bool.
- `randomizeGlobalEffect`: Bool (random from all templates; OFF = carry forward prior clip global chain).
- `clipLengthMin/Max`: Double (default 2–15).

## Phase 3: Playback semantics (replace Watch timer)

Goal: remove the watch timer and make playback event-driven.

Hard requirement:
- clips advance on clip end; if at end of tape, generate next (∞) or loop within run (finite N).

Implementation options (pick one):

1) **Player-driven end callback** (ideal):
   - the preview player emits “clip ended” at the end of clip duration
   - Dream advances tape index / generates next

2) **Timer-driven end** (acceptable first pass):
   - schedule a timer for current clip duration adjusted by play rate
   - robust to pause/seek needs extra handling (may be fragile)

This phase also decides whether “finite N” is a fixed window (first N) or a moving window (most recent N). The overview assumes “ensure there are N materialized; loop within those N”.

## Phase 4: Render clip tape (minimal UI)

Goal: export a concatenation of materialized clips (hard cuts), matching preview.

Minimal render UX:

- Finite N: render the current N-clip run.
- ∞: prompt for “render last N clips”.

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
