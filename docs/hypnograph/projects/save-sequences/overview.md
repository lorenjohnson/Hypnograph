# Save Sequences (Clip History Ranges): Overview

**Created**: 2025-01-16  
**Status**: Proposal / Planning

Goal: add a clean, predictable way to **save and render a sequence of clips** from the existing persistent clip history, without re-introducing “Sequence mode”.

This project assumes the current architecture:
- `HypnogramRecipe.clips` is the materialized clip list.
- `DreamPlayerState.currentClipIndex` selects the active clip for preview.
- Clip history is persisted separately (e.g. `clip-history.json`).
- “Save Hypnogram” saves the **current clip only** (default behavior we keep).

## Core idea

A “sequence” is just a **contiguous range of clips** from clip history.

We provide a lightweight range selection mechanism that is stable under deletion/trimming:
- **In / Out points** stored as **clip ids** (not indices).
- Default is “single clip”: In = Out = current clip.

## UX goals

- Keep preview and export coherent: exports only use clips that already exist in history (no randomization at export time).
- Keep UI minimal: two range marks (In/Out) plus a render/save action.
- Keep it hard-cut for now (transitions are out of scope).

## What “save” means

Two distinct operations:

- **Save Hypnogram**: save current clip only (existing default; keeps “hypnogram” meaning).
- **Save Sequence** (new): save the selected In→Out range as a multi-clip `.hypno` recipe file.

## What “render” means

- **Render Sequence** (new): export a movie by concatenating clips in the selected In→Out range using the same layered montage renderer used for single clips.

## Range defaults

When the user has not explicitly set In/Out:
- In = Out = current clip (so Save/Render produce the same “single clip” result as today).

Optional convenience (later, if needed):
- “Set In to Current”
- “Set Out to Current”
- “Clear In/Out (reset to current)”

## Loading multi-clip recipes (forward-looking)

When we later load multi-clip `.hypno` recipes:
- Append all loaded clips into clip history.
- Set In/Out to the newly loaded range (so “Render Sequence” is immediately meaningful).

