# Save Sequences (Clip History Ranges): Implementation Planning

**Created**: 2025-01-16  
**Status**: Draft

This plan assumes the unified “clip history” architecture is already in place (single preview path, `recipe.clips`, `currentClipIndex`, and persisted clip history).

## Phase 0: Define the selection model (In/Out)

Goal: represent an export/save selection as a range that survives deletes and history trimming.

- Add In/Out points to the persisted clip-history state:
  - `inClipID: UUID?`
  - `outClipID: UUID?`
- Interpret missing values as “single clip selection”:
  - In = Out = current clip
- Store by clip id (not index) so:
  - Deleting a clip doesn’t silently shift the selection.
  - Trimming oldest history doesn’t re-point the selection.

Edge cases:
- If an id no longer exists (deleted/trimmed), fall back to current clip.
- If In occurs after Out in the current list order, swap or treat as invalid and fall back (pick one and be consistent).

## Phase 1: UI + commands

Goal: minimal, obvious operations with no “sequence mode”.

Add menu commands (names can match product language later):
- “Set In”
- “Set Out”
- “Clear In/Out” (reset to current clip)
- “Save Sequence…” (writes multi-clip `.hypno`)
- “Render Sequence…” (exports movie for the range)

HUD/feedback (lightweight):
- Flash “IN” / “OUT” indicators when setting marks (similar style to existing HUD flashes).
- Flash a short summary when saving/rendering begins (e.g. “Rendering 7 clips…”).

## Phase 2: Save Sequence (.hypno) behavior

Goal: save a multi-clip recipe file that exactly describes the selected range.

- Compute the selected `[HypnogramClip]` by walking the clip list between In and Out (inclusive).
- Write `.hypno` using the existing recipe serializer (now that recipes can contain `clips: [...]`).
- Keep “Save Hypnogram” unchanged (current clip only).

Loading behavior (if we support it in this project):
- Loading a multi-clip `.hypno` appends all clips to history and sets In/Out to the loaded range.

## Phase 3: Render Sequence (concatenate clips)

Goal: export a movie that matches the selected range, using the same per-clip layered renderer.

Minimum viable approach:
- Render each clip using the existing single-clip render path (one movie per clip).
- Concatenate the rendered clip movies into one export:
  - Build an `AVMutableComposition` by appending each rendered `AVAsset` in order.
  - Export to the chosen output location.

Notes:
- This keeps correctness and “preview == render” without redesigning the compositor immediately.
- Hard cuts only (no transitions yet).

## Phase 4: Cleanup + ergonomics

- Ensure the export path uses the current global output settings (aspect ratio, resolution, audio policy).
- Ensure selection is deterministic and discoverable:
  - Default selection remains single clip until In/Out is set.
- Keep this project from “growing a timeline editor”:
  - No reordering, no arbitrary picking, no UI list selection (for now).

