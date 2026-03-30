---
doc-status: draft
---

# Sequence FCPXML Export

## Overview

This project separates NLE handoff from both the `Sequences` UI work and the primary sequence-render project. The working direction is that Hypnograph should eventually be able to export an authored sequence range as a package for Final Cut Pro and, ideally, DaVinci Resolve.

The first practical shape for that handoff is not raw-source interchange. Instead, Hypnograph should render each composition in the selected sequence range to its own video clip, then emit an FCPXML timeline that references those rendered clips in order. That keeps the first export path pragmatic and avoids making Apple Photos-backed source resolution, live layer reconstruction, or exact source-layer fidelity the initial interoperability boundary.

This project should also preserve traceability. Even if the NLE receives flattened rendered composition clips, the export package should ideally include enough metadata to trace those clips back to the source compositions and original media that produced them.

## Rules

- MUST treat this project as downstream of both [Sequences](/Users/lorenjohnson/dev/Hypnograph/docs/active/sequences.md) and [sequence-render-and-export.md](/Users/lorenjohnson/dev/Hypnograph/docs/backlog/sequence-render-and-export.md).
- MUST treat rendered per-composition clips plus an FCPXML timeline as the first export target.
- MUST preserve selected sequence order and selected sequence boundaries in the emitted timeline.
- MUST NOT require direct raw-layer or Apple Photos-backed source interchange for v1.
- SHOULD support Final Cut Pro first and treat DaVinci Resolve compatibility as an important secondary check.
- SHOULD include provenance metadata or a sidecar manifest so exported clips can be traced back to Hypnograph compositions and original sources.
- MAY later expand toward richer source-level interchange, but MUST treat that as separate from the first useful export path.

## Plan

- Smallest meaningful next slice: define the export package shape in plain language, including rendered clip layout, FCPXML placement, and any provenance sidecar manifest.
- Immediate acceptance check: a short authored sequence range can export as rendered clips plus an FCPXML file that imports into Final Cut Pro with the expected order and durations.
- Follow-on slice: test whether the same package shape imports acceptably into DaVinci Resolve, and document any compatibility limits.

## Open Questions

- Should the default package reference rendered clips in place, or should it copy them into a dedicated export folder for a more self-contained handoff?
- What provenance metadata is most useful to include for each rendered composition clip?
- Is Resolve compatibility required for the first version, or is Final Cut Pro success enough to ship the first pass?
- Should richer source-level export ever become its own later project, especially if Photos-backed source resolution remains too brittle?
