# Save Sequences (Clip History Ranges)

**Created**: 2025-01-16
**Status**: Proposal / Planning

## Overview

Goal: add a clean, predictable way to **save and render a sequence of clips** from the existing persistent clip history, without re-introducing "Sequence mode".

This project assumes the current architecture:
- `HypnogramRecipe.clips` is the materialized clip list.
- `DreamPlayerState.currentClipIndex` selects the active clip for preview.
- Clip history is persisted separately (e.g. `clip-history.json`).
- "Save Hypnogram" saves the **current clip only** (default behavior we keep).

### Core idea

A "sequence" is just a **contiguous range of clips** from clip history.

We provide a lightweight range selection mechanism that is stable under deletion/trimming:
- **In / Out points** stored as **clip ids** (not indices).
- Default is "single clip": In = Out = current clip.

### UX goals

- Keep preview and export coherent: exports only use clips that already exist in history (no randomization at export time).
- Keep UI minimal: two range marks (In/Out) plus a render/save action.
- Keep it hard-cut for now (transitions are out of scope).

### What "save" means

Two distinct operations:

- **Save Hypnogram**: save current clip only (existing default; keeps "hypnogram" meaning).
- **Save Sequence** (new): save the selected In→Out range as a multi-clip `.hypno` recipe file.

### What "render" means

- **Render Sequence** (new): export a movie by concatenating clips in the selected In→Out range using the same layered montage renderer used for single clips.

### Range defaults

When the user has not explicitly set In/Out:
- In = Out = current clip (so Save/Render produce the same "single clip" result as today).

Optional convenience (later, if needed):
- "Set In to Current"
- "Set Out to Current"
- "Clear In/Out (reset to current)"

### Loading multi-clip recipes (forward-looking)

When we later load multi-clip `.hypno` recipes:
- Append all loaded clips into clip history.
- Set In/Out to the newly loaded range (so "Render Sequence" is immediately meaningful).

---

## Implementation Plan

This plan assumes the unified "clip history" architecture is already in place (single preview path, `recipe.clips`, `currentClipIndex`, and persisted clip history).

### Phase 0: Define the selection model (In/Out)

Goal: represent an export/save selection as a range that survives deletes and history trimming.

- Add In/Out points to the persisted clip-history state:
  - `inClipID: UUID?`
  - `outClipID: UUID?`
- Interpret missing values as "single clip selection":
  - In = Out = current clip
- Store by clip id (not index) so:
  - Deleting a clip doesn't silently shift the selection.
  - Trimming oldest history doesn't re-point the selection.

Edge cases:
- If an id no longer exists (deleted/trimmed), fall back to current clip.
- If In occurs after Out in the current list order, swap or treat as invalid and fall back (pick one and be consistent).

### Phase 1: UI + commands

Goal: minimal, obvious operations with no "sequence mode".

Add menu commands (names can match product language later):
- "Set In"
- "Set Out"
- "Clear In/Out" (reset to current clip)
- "Save Sequence…" (writes multi-clip `.hypno`)
- "Render Sequence…" (exports movie for the range)

HUD/feedback (lightweight):
- Flash "IN" / "OUT" indicators when setting marks (similar style to existing HUD flashes).
- Flash a short summary when saving/rendering begins (e.g. "Rendering 7 clips…").

### Phase 2: Save Sequence (.hypno) behavior

Goal: save a multi-clip recipe file that exactly describes the selected range.

- Compute the selected `[HypnogramClip]` by walking the clip list between In and Out (inclusive).
- Write `.hypno` using the existing recipe serializer (now that recipes can contain `clips: [...]`).
- Keep "Save Hypnogram" unchanged (current clip only).

Loading behavior (if we support it in this project):
- Loading a multi-clip `.hypno` appends all clips to history and sets In/Out to the loaded range.

### Phase 3: Render Sequence (concatenate clips)

Goal: export a movie that matches the selected range, using the same per-clip layered renderer.

Minimum viable approach:
- Render each clip using the existing single-clip render path (one movie per clip).
- Concatenate the rendered clip movies into one export:
  - Build an `AVMutableComposition` by appending each rendered `AVAsset` in order.
  - Export to the chosen output location.

Notes:
- This keeps correctness and "preview == render" without redesigning the compositor immediately.
- Hard cuts only (no transitions yet).

### Phase 4: Cleanup + ergonomics

- Ensure the export path uses the current global output settings (aspect ratio, resolution, audio policy).
- Ensure selection is deterministic and discoverable:
  - Default selection remains single clip until In/Out is set.
- Keep this project from "growing a timeline editor":
  - No reordering, no arbitrary picking, no UI list selection (for now).
