---
doc-status: draft
---

# Sequence Render and Export

## Status

The first useful version of this project has landed: Hypnograph can now export a full hypnogram as one finished movie through the shared sequence-time renderer.

The architecture reference now lives here:

- [render-pipeline](../reference/render-pipeline.md)

This backlog item now covers the follow-on work around that export path rather than the initial landing of sequence export itself.

## Rules

- MUST treat this project as downstream of [Sequences](/Users/lorenjohnson/dev/Hypnograph/docs/active/sequences.md), not as the driver of sequence UI design.
- MUST preserve the selected sequence order and sequence boundaries shown in the sequence UI.
- MUST include sequence-level timing and transitions in the finished rendered movie when those behaviors exist in Hypnograph.
- SHOULD reuse the existing render destination model where practical rather than inventing a completely separate export-storage system.
- SHOULD clarify whether sequence renders live alongside ordinary Hypnograph renders or in a distinct subfolder or naming scheme.
- MUST NOT require NLE interchange or FCPXML support in order to ship the first useful sequence render flow.

## Plan

- Smallest meaningful next slice: connect the selected sequence range from the `Sequences` UI into the existing sequence-time renderer rather than always rendering the whole saved hypnogram.
- Immediate acceptance check: a selected range of multiple compositions can be rendered as one finished movie whose duration and ordering match the sequence selection shown in the UI.
- Follow-on slice: add export progress, better operator feedback, and performance instrumentation that reflects sequence-time assembly rather than stitched composition exports.

## Open Questions

- Should sequence render use the same destination and naming model as current Hypnograph renders, or should sequence output have its own naming or folder convention?
- If the selected range includes compositions that would currently auto-generate further history during playback, how is that generation boundary frozen for the render?
- Which sequence-level transitions or handoff behaviors are required for the first useful rendered output, and which can be deferred?
