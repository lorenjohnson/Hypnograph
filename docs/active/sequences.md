---
doc-status: ready
---

# Sequences

## Overview

This project is about adding the first real sequence-authoring surface on top of Hypnograph's existing history model. The MVP is a history timeline strip that makes the sequence of compositions visible and editable as a range, without turning Hypnograph into a full non-linear editor.

The core UI should look and feel like the existing composition and layer timeline controls, but operate across history. It should show whole compositions as segments, support in and out points that snap to composition boundaries, and make it much clearer where the operator is in history and what portion of history is being treated as the active sequence.

This project also needs to deal with the fact that history can be large. The default history size is on the order of hundreds of items, so the sequence strip likely needs some combination of zooming, scaling, or condensed overview behavior rather than assuming that every composition can remain equally legible at once.

There are still significant open questions inside this project. The most important ones are about behavior rather than visuals: what `Play` should do from mid-history, what `New` should do from mid-history, whether authored compositions can eventually be inserted or reordered within history, and how range boundaries should interact with transport actions like jumping to the beginning or end.

Export has now been split out as follow-on work. This project stays focused on sequence definition and control inside Hypnograph. Rendering authored ranges and NLE handoff are tracked separately in [sequence-render-and-export.md](/Users/lorenjohnson/dev/Hypnograph/docs/backlog/sequence-render-and-export.md) and [sequence-fcpxml-export.md](/Users/lorenjohnson/dev/Hypnograph/docs/backlog/sequence-fcpxml-export.md).

## Rules

- MUST keep the current history-based model usable while adding sequence authorship on top of it.
- MUST prototype a history timeline strip that uses the same general styling language as the existing composition or layer timelines.
- MUST let the operator set an in point and an out point across history.
- MUST let history range selection snap to whole-hypnogram boundaries rather than arbitrary sub-clip positions.
- MUST make the history strip capable of dealing with large histories rather than assuming only a handful of visible items.
- SHOULD treat show or hide behavior for the history timeline and the existing hypnogram timeline as one coordinated UX decision.
- MUST clarify what `Play` does when the operator is parked on an older history item and loop mode is off.
- MUST clarify what semantic reference point is used when creating a new hypnogram from older history.
- SHOULD add clearer transport affordances for jumping to the beginning and end of the active range or history, if that remains the clearest MVP control shape.
- SHOULD test insertion at the current history position as the preferred authoring behavior for `New` if the model cost is acceptable.
- MUST keep export concerns from taking over the first sequence UI and behavior decisions.
- MUST NOT let longer-term naming or model-cleanup questions block the first usable version.

## Plan

- Smallest meaningful next slice: define the first history timeline strip in plain language, including its visible segments, range handles, snap behavior, and how it behaves when history becomes too dense to show at full detail.
- Immediate acceptance check: the operator can see history as a strip of compositions and set a whole-composition in and out range without ambiguity.
- Follow-on slice: clarify transport semantics from within that selected range, especially `Play`, `New`, and whether beginning/end buttons should target the full history or the active selected range.

## Open Questions

- Should `New` from mid-history eventually insert at the current position, or continue appending at the live end while only changing carry-forward semantics?
- Should `Play` from mid-history continue through older history, return into live generation, or become range-aware once in and out points exist?
- Should beginning and end transport buttons jump to the full history bounds, or to the current selected range once one exists?
- What is the clearest first way to handle hundreds of history items in the strip: zoom, overview + focus, collapsing, or something else?
- Is moving or reordering compositions within the sequence in scope for this first project, or only something to leave open while the basic range-selection model settles?
