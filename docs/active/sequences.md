---
doc-status: in-progress
---

# Sequences

## Overview

This project is about turning Hypnograph's evolving history into a first real sequence-authoring surface.

The core model is now clear: there is one active working `Hypnogram` at a time. If the app is launched normally, that working hypnogram is the default autosaved `history.json` session. If a `.hypno` file is opened, that file replaces the active working hypnogram. Sequence UI and behavior should build on that document model rather than treating history as a separate architecture.

The next visible milestone is a sequence strip or timeline that makes the compositions in the current working hypnogram visible and editable as an ordered range. Export remains follow-on work and is tracked separately in [sequence-render-and-export.md](/Users/lorenjohnson/dev/Hypnograph/docs/backlog/sequence-render-and-export.md) and [sequence-fcpxml-export.md](/Users/lorenjohnson/dev/Hypnograph/docs/backlog/sequence-fcpxml-export.md).

## Rules

- MUST keep the current history-based model usable while adding sequence authorship on top of it.
- MUST prototype a history timeline strip that uses the same general styling language as the existing composition or layer timelines.
- MUST let the operator set an in point and an out point across history.
- MUST let history range selection snap to whole-hypnogram boundaries rather than arbitrary sub-clip positions.
- MUST make the history strip capable of dealing with large histories rather than assuming only a handful of visible items.
- MUST treat history persistence convergence with the saved `Hypnogram` document format as in scope for this project rather than as unrelated cleanup.
- MUST treat `currentCompositionIndex` as optional multi-composition document state on `Hypnogram`, not as a history-only sidecar format.
- MUST establish composition-level preview image fields so sequence and history UI can render composition thumbnails without inventing a history-only image model.
- MUST treat document-level viewing or restore context such as aspect ratio, player or output resolution, source framing, and transition style or duration as optional state on `Hypnogram` rather than only as app-global settings.
- MUST deprecate the previous app-global persistence locations for those document-level viewing fields rather than carrying forward migration support for them.
- MUST keep `playRate` as composition-level authored data rather than moving it into hypnogram-level document state.
- SHOULD treat show or hide behavior for the history timeline and the existing hypnogram timeline as one coordinated UX decision.
- MUST clarify what `Play` does when the operator is parked on an older history item and loop mode is off.
- MUST clarify what semantic reference point is used when creating a new hypnogram from older history.
- SHOULD add clearer transport affordances for jumping to the beginning and end of the active range or history, if that remains the clearest MVP control shape.
- SHOULD test insertion at the current history position as the preferred authoring behavior for `New` if the model cost is acceptable.
- MUST keep export concerns from taking over the first sequence UI and behavior decisions.
- MUST NOT let longer-term naming or model-cleanup questions block the first usable version.

## Plan

- Completed slice: history persistence now validates as a shared multi-composition `Hypnogram`, with composition-level previews and canonical `currentCompositionIndex`.
- Completed slice: document-level restore context now lives on `Hypnogram`, not in app-global settings. `playRate` remains composition-level.
- Completed slice: the active working document model now distinguishes between the unnamed default session and file-backed `.hypno` documents without treating history as a different data model.
- Next slice: simplify runtime ownership so the current working `Hypnogram` is clearly owned by `Studio` and document-level settings stop being mirrored across multiple runtime homes.
- Follow-on slice: define the first sequence strip or timeline surface, including segment visibility, range selection, and how dense histories are made legible.
- Later slice: clarify sequence transport behavior such as `Play`, `New`, and beginning/end navigation once a visible sequence range exists.

## Open Questions

- Should the top-level `Hypnogram.snapshot` remain as a stored document-poster image, or become a derived accessor that simply returns the first composition's preview image?
- Should `New` from mid-history eventually insert at the current position, or continue appending at the live end while only changing carry-forward semantics?
- Should `Play` from mid-history continue through older history, return into live generation, or become range-aware once in and out points exist?
- What is the clearest first way to handle hundreds of history items in the strip: zoom, overview + focus, collapsing, or something else?
- Is moving or reordering compositions within the sequence in scope for this first project, or only something to leave open while the basic range-selection model settles?
- Before this project is done, revisit the `history` naming in both code and UI so it more honestly describes the unnamed scratch session or default working document rather than implying a separate model.
- That same pass should resolve scratch-session edge cases, such as what should happen after explicitly saving the scratch session as a file-backed hypnogram and whether the default scratch session should immediately reset to a fresh working document afterward.

## Architecture Direction

The current working `Hypnogram` should be the central Studio document model.

That means:
- `Studio` should ultimately own the active working `Hypnogram`.
- `PlayerState` should shrink toward playback-local concerns such as pause state, current layer selection, scrubbing offsets, load failures, and frame-presentation tracking.
- Document-shaped state that loads from a file, updates while authoring, and saves back into the file should live on the current working `Hypnogram`, not be mirrored across multiple semi-authoritative runtime homes.
- App-global concerns such as libraries, permissions, and global preferences should remain outside the document.

## Current Implementation State

- History persistence now uses the shared multi-composition `Hypnogram` schema rather than a separate history-only shape.
- Composition-level `snapshot` and `thumbnail` fields are now in place and are used for history-item previews.
- `currentCompositionIndex` is now treated as optional document state on `Hypnogram`.
- Document-level viewing and playback settings such as aspect ratio, player or output resolution, source framing, and transition settings have been moved off app-global settings and onto `Hypnogram`.
- Opening a `.hypno` file now replaces the active working hypnogram instead of appending into the default autosaved history document.
- The default `history.json` now effectively behaves as the unnamed fallback working hypnogram and is only autosaved while it remains the active document.
- `Save` and `Save As` now save the full current working hypnogram, while `Save Composition` and `Save Composition As` explicitly save only the current composition as a single-composition `.hypno`.
- File-open replacement now prompts to save only when the current active working document is a dirty file-backed hypnogram. The unnamed default history document is simply autosaved and replaced.
- The current implementation of those moved settings is still transitional. The data shape is correct, but runtime ownership is still split across `Studio`, `PlayerState`, `LivePlayer`, and player configuration in a way that is more mirrored than the desired end state.

## Next Refactor

This session is intentionally pausing here. The next clean architectural step is not to add more fields or more migration support, but to simplify runtime ownership around the already-established model shape.

- Move ownership of the current working `Hypnogram` to `Studio`.
- Reduce `PlayerState` so it holds playback-local concerns rather than owning the document itself.
- Let document-level settings live as current-hypnogram state first, with runtime systems applying from and syncing back to that single source of truth.
- Remove avoidable mirrored state for those document-level settings where possible, especially where the current implementation is carrying both runtime values and hypnogram copies only to keep them aligned.


---

MISC ADDENDUM:

After we move Hypnogram up to Studio state:

- Can't seem to change output resolution

- Snapshot saving I think is causing pauses in transitions at the end of clips. It is crucial we don't interrupt playback.

- UX issue (old): There is a weird broken / mismatch pattern between the effects (chains) on Composition and Layer mostly in terms of the menus, but ultimately related to underlying out-of-date functionality in the Layer effect chain cycling.

- Rename the Playback menu to Sequence, also the History tab in Hypnograms panel should be renamed to "Sequence" or simply "Current"

- The ability to re-order items in the Sequence by drag-and-drop within the Hypnogram > Sequence (assuming the code can be re-used as we move to a Timeline view) would be a big win
- 
- The delineation between History and a currently open Hypnogram file needs to be possible first, and then clear on how to switch between them.  The endpoint of the bulk of non-timeline UI sequences will be getting to thise point of having sort of clear UX for switching between History "mode" and the current Hypnogram file.  How those relate and interact...
