---
doc-status: in-progress
---

# Sequences

## Overview

This project is about adding the first real sequence-authoring surface on top of Hypnograph's existing history model. The MVP is a history timeline strip that makes the sequence of compositions visible and editable as a range, without turning Hypnograph into a full non-linear editor.

The core UI should look and feel like the existing composition and layer timeline controls, but operate across history. It should show whole compositions as segments, support in and out points that snap to composition boundaries, and make it much clearer where the operator is in history and what portion of history is being treated as the active sequence.

This project also needs to deal with the fact that history can be large. The default history size is on the order of hundreds of items, so the sequence strip likely needs some combination of zooming, scaling, or condensed overview behavior rather than assuming that every composition can remain equally legible at once.

There are still significant open questions inside this project. The most important ones are about behavior rather than visuals: what `Play` should do from mid-history, what `New` should do from mid-history, whether authored compositions can eventually be inserted or reordered within history, and how range boundaries should interact with transport actions like jumping to the beginning or end.

Export has now been split out as follow-on work. This project stays focused on sequence definition and control inside Hypnograph. Rendering authored ranges and NLE handoff are tracked separately in [sequence-render-and-export.md](/Users/lorenjohnson/dev/Hypnograph/docs/backlog/sequence-render-and-export.md) and [sequence-fcpxml-export.md](/Users/lorenjohnson/dev/Hypnograph/docs/backlog/sequence-fcpxml-export.md).

The first active implementation slice is now lower-level than the visible sequence strip. Before the sequence UI grows much further, history persistence should stop using its own near-duplicate file schema and instead validate as the same multi-composition `Hypnogram` document shape used for saved `.hypno` files. That means establishing composition-level preview images that future sequence UI can rely on, and treating `currentCompositionIndex` as optional document state on the multi-composition hypnogram itself rather than as a separate history-only side channel.

The next shape behind that is to let the working multi-composition hypnogram carry optional document context for how it was being viewed and authored. That includes things like aspect ratio, player or output resolution, source framing, and transition style or duration. Those are not being treated as authoritative authored sequence content; they are document-level reference points for restoring the working state of a hypnogram. `playRate` is explicitly not part of that move and remains composition-level authored data.

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

- Smallest meaningful next slice: make history persistence validate as a `Hypnogram`-shaped multi-composition document, store the current selected composition index canonically on that document, and add composition-level `snapshot` and `thumbnail` fields generated off the playback-critical path.
- Immediate acceptance check: the app can persist and restore history using the shared hypnogram schema, composition previews exist at the composition level, and the current history position still restores correctly from the hypnogram document itself.
- Next model slice: move document viewing context from app-global settings toward optional `Hypnogram` fields such as `aspectRatio`, `playerResolution`, `outputResolution`, and `sourceFraming`, while leaving `playRate` on `Composition`.
- Follow-on slice: define the first history timeline strip in plain language, including its visible segments, range handles, snap behavior, and how it behaves when history becomes too dense to show at full detail.
- Later follow-on slice: clarify transport semantics from within that selected range, especially `Play`, `New`, and whether beginning/end buttons should target the full history or the active selected range.

## Open Questions

- Should the top-level `Hypnogram.snapshot` remain as a stored document-poster image, or become a derived accessor that simply returns the first composition's preview image?
- Should both `snapshot` and `thumbnail` live on `Composition`, or should only one of those be stored canonically with the other derived on demand?
- Should `New` from mid-history eventually insert at the current position, or continue appending at the live end while only changing carry-forward semantics?
- Should `Play` from mid-history continue through older history, return into live generation, or become range-aware once in and out points exist?
- Should beginning and end transport buttons jump to the full history bounds, or to the current selected range once one exists?
- What is the clearest first way to handle hundreds of history items in the strip: zoom, overview + focus, collapsing, or something else?
- Is moving or reordering compositions within the sequence in scope for this first project, or only something to leave open while the basic range-selection model settles?

## Architecture Direction

The current working `Hypnogram` should become the central document model in Studio rather than remaining conceptually subordinate to the player. In practice, that means the loaded hypnogram, which is currently usually the app's history document, should live at the Studio level and become the source of truth for multi-composition state, composition previews, selection state, and document-level viewing or playback settings such as aspect ratio, player or output resolution, source framing, and transition settings.

The important implication is that this project should not invent a separate document-context model if the current working hypnogram can already hold that state. The cleaner end state is for `Studio` to own the current working `Hypnogram`, for `PlayerState` to shrink back toward playback-local concerns such as pause state, current layer selection, scrubbing offsets, load failures, and frame-presentation tracking, and for runtime settings edits to flow back into the current hypnogram directly rather than being mirrored across several semi-authoritative homes.

This does not require every app-global setting to move into the hypnogram. Library setup, permissions, and similar app-wide concerns still belong above the document. But document-shaped state that should load from a file, update live while authoring, and save back into the file should increasingly be treated as current-hypnogram state rather than as scattered player or settings-store state.

## Current Implementation State

- History persistence now uses the shared multi-composition `Hypnogram` schema rather than a separate history-only shape.
- Composition-level `snapshot` and `thumbnail` fields are now in place and are used for history-item previews.
- `currentCompositionIndex` is now treated as optional document state on `Hypnogram`.
- Document-level viewing and playback settings such as aspect ratio, player or output resolution, source framing, and transition settings have been moved off app-global settings and onto `Hypnogram`.
- The current implementation of those moved settings is still transitional. The data shape is correct, but runtime ownership is still split across `Studio`, `PlayerState`, `LivePlayer`, and player configuration in a way that is more mirrored than the desired end state.

## Next Refactor

This session is intentionally pausing here. The next clean architectural step is not to add more fields or more migration support, but to simplify runtime ownership around the already-established model shape.

- Move ownership of the current working `Hypnogram` to `Studio`.
- Reduce `PlayerState` so it holds playback-local concerns rather than owning the document itself.
- Let document-level settings live as current-hypnogram state first, with runtime systems applying from and syncing back to that single source of truth.
- Remove avoidable mirrored state for those document-level settings where possible, especially where the current implementation is carrying both runtime values and hypnogram copies only to keep them aligned.

## Current Direction

- History should converge toward the same schema as a saved multi-composition `Hypnogram`, rather than preserving a separate `HistoryFile` structure with mostly duplicated fields.
- The current meaningful difference between history persistence and saved hypnograms is shrinking further. Selection restore state should be allowed to live on the multi-composition `Hypnogram` itself as optional `currentCompositionIndex` document state.
- Composition previews should become composition-owned data. The current top-level hypnogram snapshot is document-level today, but sequence UI needs thumbnail and snapshot data per composition.
- Preview generation should happen when a composition becomes a history item or a saved document element, and it should happen off the playback-critical path so live playback is not slowed down.
- Existing source-media timeline thumbnail systems such as `TimelineThumbnailStore` remain separate. They solve layer and scrubbing UI problems, not composition-history preview problems.
- The current working history document should increasingly become the canonical source of restore state for the app, rather than duplicating that same state in separate app-setting channels when the data is really about the open multi-composition hypnogram.
- The likely next document-level fields are optional hypnogram values such as aspect ratio, player or output resolution, source framing, and transition style or duration. These are restore hints for the open hypnogram, not authoritative authored content.
- The older app-global persistence locations for those fields should be removed rather than migrated. If older app installs lose those specific values once, that is acceptable.
- `playRate` remains where it is now as an attribute of each composition, because it affects the authored behavior of that composition rather than only the document viewing context.


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

