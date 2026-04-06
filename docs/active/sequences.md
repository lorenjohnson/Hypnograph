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

The first active implementation slice is now lower-level than the visible sequence strip. Before the sequence UI grows much further, history persistence should stop using its own near-duplicate file schema and instead validate as the same multi-composition `Hypnogram` document shape used for saved `.hypno` files. That means moving selection restore state such as `currentCompositionIndex` out of the history payload and into app restore state, while also establishing composition-level preview images that future sequence UI can rely on.

## Rules

- MUST keep the current history-based model usable while adding sequence authorship on top of it.
- MUST prototype a history timeline strip that uses the same general styling language as the existing composition or layer timelines.
- MUST let the operator set an in point and an out point across history.
- MUST let history range selection snap to whole-hypnogram boundaries rather than arbitrary sub-clip positions.
- MUST make the history strip capable of dealing with large histories rather than assuming only a handful of visible items.
- MUST treat history persistence convergence with the saved `Hypnogram` document format as in scope for this project rather than as unrelated cleanup.
- MUST move `currentCompositionIndex`-style selection restore state out of the persisted history document and into app restore state.
- MUST establish composition-level preview image fields so sequence and history UI can render composition thumbnails without inventing a history-only image model.
- SHOULD treat show or hide behavior for the history timeline and the existing hypnogram timeline as one coordinated UX decision.
- MUST clarify what `Play` does when the operator is parked on an older history item and loop mode is off.
- MUST clarify what semantic reference point is used when creating a new hypnogram from older history.
- SHOULD add clearer transport affordances for jumping to the beginning and end of the active range or history, if that remains the clearest MVP control shape.
- SHOULD test insertion at the current history position as the preferred authoring behavior for `New` if the model cost is acceptable.
- MUST keep export concerns from taking over the first sequence UI and behavior decisions.
- MUST NOT let longer-term naming or model-cleanup questions block the first usable version.

## Plan

- Smallest meaningful next slice: make history persistence validate as a `Hypnogram`-shaped multi-composition document, move current selection restore state out of that document, and add composition-level `snapshot` and `thumbnail` fields generated off the playback-critical path.
- Immediate acceptance check: the app can persist and restore history using the shared hypnogram schema, composition previews exist at the composition level, and the current history position still restores correctly from app state.
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

## Current Direction

- History should converge toward the same schema as a saved multi-composition `Hypnogram`, rather than preserving a separate `HistoryFile` structure with mostly duplicated fields.
- The current meaningful difference between history persistence and saved hypnograms is selection restore state. That should live in app state, not inside the persisted history document.
- Composition previews should become composition-owned data. The current top-level hypnogram snapshot is document-level today, but sequence UI needs thumbnail and snapshot data per composition.
- Preview generation should happen when a composition becomes a history item or a saved document element, and it should happen off the playback-critical path so live playback is not slowed down.
- Existing source-media timeline thumbnail systems such as `LayerThumbnailStore` remain separate. They solve layer and scrubbing UI problems, not composition-history preview problems.
