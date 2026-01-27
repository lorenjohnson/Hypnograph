# Record Deck (VCR HUD + Recording)

**Created**: 2026-01-27  
**Status**: Proposal / Planning

## Summary

Replace “mark IN/OUT range and export” with a simpler mental model:

> A **Record** button that captures what you play (like a VCR/tape deck).

This project also introduces a **bottom playback HUD** (auto-hides with the cursor) with:
- Play / Pause
- Previous / Next (wired to existing history navigation)
- **Record / Stop** (new)

This project **fully replaces** the prior “Save Sequences (clip history ranges)” plan.

## Goals

- Make “saving a sequence” feel like recording a performance rather than marking a range.
- Reduce the number of concepts users must learn (no IN/OUT jargon in the primary UX).
- Make “Render & Save” naturally flow from recording (Record → Stop → Save).
- Keep controls minimal and wire them to existing behaviors (no new “scrub rewind” feature required).
- Preserve all capabilities of the old “save sequences” plan (multi-clip save + render).

## UX Requirements

### 1) HUD Controls

- A bottom overlay control strip, styled like a retro/pro video deck.
- Shows on mouse movement; hides when idle (same behavior as cursor auto-hide).
- Buttons:
  - **Prev**: existing “previous clip” (history/back)
  - **Play/Pause**: existing pause toggle
  - **Next**: existing “next clip” (history/forward)
  - **Record/Stop**: new

### 2) Record Behavior

- If user presses **Record while paused**, it should **start playing and recording immediately**.
- Recording continues across clip-history navigation (prev/next).
- Pressing **Stop** ends the recording.

### 3) Output

- On Stop, prompt for save target/name (or route into the existing render/save flow).
- MVP can export using the existing RenderEngine pipeline.

## Core Model (In/Out Under the Hood)

Even though the UI is “Record/Stop”, the underlying selection should still be a **contiguous clip
range** (In/Out) from clip history so it is stable and deterministic.

- Store selection by **clip IDs**, not indices:
  - `inClipID: UUID?`
  - `outClipID: UUID?`
- Default selection (no record): **single clip** (`in = out = current clip`)
- If an ID no longer exists (trimmed/deleted), fall back to current clip.
- If In occurs after Out in list order, swap or treat as invalid (be consistent).

Record button mapping:
- **Record** → set In to current clip (if not already recording)
- **Stop** → set Out to current clip

## Save vs Render (What Each Means)

- **Save Hypnogram**: current behavior, saves **current clip only**
- **Save Recording** (new): save the selected In→Out range as a multi-clip `.hypno` recipe
- **Render Recording** (new): export a movie by concatenating clips in the selected range

## Range Defaults

If the user never records:
- In = Out = current clip (so save/render behaves exactly like today)

## Loading Multi-Clip Recipes (Forward-Looking)

When a multi-clip `.hypno` is loaded:
- Append its clips into history.
- Set In/Out to the newly loaded range for immediate re-rendering if desired.

## MVP Implementation Strategy (Low Risk)

To keep scope manageable for a beta:

- Implement Record/Stop as a friendly wrapper over the existing “save sequence range” concept:
  - Record → sets “IN” mark at current history index/time.
  - Stop → sets “OUT” mark at current history index/time.
  - Then export the range using the same underlying mechanism.

This lets us ship the new UX without committing to a full “record to file in real time” capture path.

## Follow-ups (Post-MVP)

- “Record to Library” (save as a reusable hypnogram or clip-history tape).
- Better naming (“Save to Library”, “Save as…”, etc.) consistent with other menus.
- Optional timeline visualization (only if needed; not required for beta).

## Implementation Phases (Carryover From Save Sequences)

### Phase 0: Define selection model
- Add In/Out IDs to persisted clip-history state.
- Interpret missing values as “single clip”.

### Phase 1: HUD + commands
- Record/Stop in HUD.
- Optional lightweight flashes (“REC”, “STOP”, or small indicator).

### Phase 2: Save Recording (.hypno)
- Serialize the selected clip range as a multi-clip recipe.

### Phase 3: Render Recording (concatenate clips)
- Render each clip using the existing single-clip renderer.
- Concatenate rendered clips into one export using `AVMutableComposition`.

### Phase 4: Cleanup + ergonomics
- Ensure output respects current global output settings.
- Keep the UX minimal (no timeline editor).

## Related Docs / Prior Art

- `docs/hypnograph/reference/controls.md` (HUD notes)
