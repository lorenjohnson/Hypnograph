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

This should **subsume** `save-sequences` (clip history ranges) as the underlying mechanism and/or
as a legacy plan.

## Goals

- Make “saving a sequence” feel like recording a performance rather than marking a range.
- Reduce the number of concepts users must learn (no IN/OUT jargon in the primary UX).
- Make “Render & Save” naturally flow from recording (Record → Stop → Save).
- Keep controls minimal and wire them to existing behaviors (no new “scrub rewind” feature required).

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

## Related Docs / Prior Art

- `docs/hypnograph/projects/save-sequences.md` (legacy planning; should be folded into this)
- `docs/hypnograph/reference/controls.md` (HUD notes)

