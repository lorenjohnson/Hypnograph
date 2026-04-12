---
doc-status: draft
---

# Sequence Render and Export

## Overview

This project separates export of authored sequences from the core `Sequences` UI and behavior work. Once Hypnograph can clearly define and select a sequence range across multiple compositions, the first export outcome should be the ability to render that authored range as one finished movie from inside Hypnograph.

The new [sequence-time-renderer](../active/sequence-time-renderer.md) work now owns the shared timing model underneath this. This backlog item should treat that model as the foundation for real sequence export rather than inventing separate export-only timing logic.

That finished render should preserve the sequence timing, transitions, and other playback results that Hypnograph itself is responsible for. The operator should not need to leave the app just to get a coherent finished movie from a selected sequence range.

This project is intentionally broader than a raw render button. It should define how a selected sequence range becomes an exportable artifact, how that maps onto the existing render destination model, and what the operator can expect when rendering a sequence versus rendering a single composition.

## Rules

- MUST treat this project as downstream of [Sequences](/Users/lorenjohnson/dev/Hypnograph/docs/active/sequences.md), not as the driver of sequence UI design.
- MUST treat single-movie render of an authored sequence range as the first export target.
- MUST preserve the selected sequence order and sequence boundaries shown in the sequence UI.
- MUST include sequence-level timing and transitions in the finished rendered movie when those behaviors exist in Hypnograph.
- SHOULD reuse the existing render destination model where practical rather than inventing a completely separate export-storage system.
- SHOULD clarify whether sequence renders live alongside ordinary Hypnograph renders or in a distinct subfolder or naming scheme.
- MUST NOT require NLE interchange or FCPXML support in order to ship the first useful sequence render flow.

## Plan

- Smallest meaningful next slice: define the operator-facing contract for rendering a selected sequence range, including where the rendered movie goes, how it is named, and what timing and transition behavior it preserves.
- Immediate acceptance check: a selected range of multiple compositions can be rendered as one finished movie whose duration and ordering match the sequence selection shown in the UI.
- Follow-on slice: connect the selected sequence range from the `Sequences` UI into the existing render/export pipeline with the smallest implementation that produces a reliable finished movie.

## Open Questions

- Should sequence render use the same destination and naming model as current Hypnograph renders, or should sequence output have its own naming or folder convention?
- If the selected range includes compositions that would currently auto-generate further history during playback, how is that generation boundary frozen for the render?
- Which sequence-level transitions or handoff behaviors are required for the first useful rendered output, and which can be deferred?
