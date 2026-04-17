---
doc-status: in-progress
---

# Sequence FCPXML Export

## Overview

This project adds a practical Final Cut Pro handoff for the current working sequence. The export should preserve editorial usefulness, not just visual playback. In the first useful version, Hypnograph should emit an FCPXML timeline that references the original source clips wherever possible, preserving the cuts and trims already made in Hypnograph without flattening the whole sequence to rendered movies.

The current practical export shape is a self-contained project directory named after the chosen project. All referenced source clips are copied into its `Media/` folder, including Apple Photos-backed sources exported through PhotoKit and normal file-backed sources copied from disk. The resulting timeline should represent the current sequence order and each composition's trimmed source clips, while explicitly leaving effects and transitions out of scope for now.

The current implementation target for v1 is:

- export the whole current working sequence, not an arbitrary selected range
- present a File menu command that creates an export directory named after the chosen project
- copy normal file-backed sources into the export directory's `Media/` folder
- export Apple Photos-backed originals into that same `Media/` folder
- preserve source trims and layer order for the current sequence
- include a small manifest sidecar for provenance
- emit FCPXML `1.8` as a single `.fcpxml` document using direct asset file URLs

## Current Status

- Current handoff branch for continued implementation: `sequence-fcpxml-export`
- The export is working partially: it creates a named export directory, writes an `.fcpxml`, packages source media into `Media/`, and imports far enough in Final Cut Pro and DaVinci Resolve to expose real timeline/media issues instead of failing immediately.
- The packaged file-backed clips still do not reliably relink on DaVinci Resolve import, even after copying them into the export directory.
- Three-layer compositions still import with only two visible layers; the third layer is still getting lost in the current multi-layer FCPXML shape.
- Basic framing/conform is partially represented, but exact cross-NLE visual parity is still unresolved.

## Pickup Notes

- Start from branch `sequence-fcpxml-export`.
- Investigate why packaged file-backed assets in `Media/` still fail to resolve in DaVinci Resolve despite valid-looking paths and copied media.
- Investigate the current multi-layer composition encoding so three-layer compositions preserve all layers on import, not just two.
- Re-test both Final Cut Pro and DaVinci Resolve after any changes, since the import failures are not identical between the two apps.

## Rules

- MUST treat this project as downstream of both [Sequences](/Users/lorenjohnson/dev/Hypnograph/docs/archive/20260414-sequences.md) and [sequence-render-and-export.md](/Users/lorenjohnson/dev/Hypnograph/docs/archive/20260414-sequence-render-and-export.md).
- MUST preserve current sequence order in the emitted timeline.
- MUST export the whole current working sequence for v1.
- MUST package all referenced source media into the export directory for the current version.
- MUST export original Apple Photos-backed media into that package for v1.
- MUST preserve clip trims from Hypnograph in the emitted timeline.
- MUST NOT require effects, transitions, or exact visual parity with Hypnograph for the first version.
- SHOULD support Final Cut Pro first and treat DaVinci Resolve compatibility as a secondary check.
- SHOULD include provenance metadata or a sidecar manifest so exported clips can be traced back to Hypnograph compositions and source media.
- MAY later add an advanced flattened export with effects applied, but MUST treat that as a follow-on mode rather than the default handoff.

## Plan

- Immediate implementation slice:
  - add a File menu command for `Export Sequence to FCPXML...`
  - let the user choose a project/export name in the save dialog
  - resolve every source layer in the current sequence to a packaged media file inside the export directory
  - emit an FCPXML timeline that preserves composition order, layer order, and trims
  - write a provenance sidecar manifest into the export directory
- Immediate acceptance check:
  - the current working sequence exports as a named directory containing a `.fcpxml`, `Media/`, and manifest
  - file-backed and Apple Photos-backed clips are both packaged into the export directory and referenced from the XML
  - the emitted timeline preserves current composition order and trimmed source ranges
  - the exported package is legible enough to attempt import into Final Cut Pro
- Follow-on slice:
  - selected-range export instead of whole-sequence-only export
  - evaluate whether simple blend/composite information is worth representing in FCPXML
  - consider an optional flattened export mode with Hypnograph effects applied

## Open Questions

- Does the implemented FCPXML `1.8` single-file export import cleanly in Final Cut Pro practice?
- Is the current gap-plus-layer structure for multi-layer compositions accepted cleanly by Final Cut Pro?
- What provenance metadata is most useful to include in the manifest for follow-up editorial work?
- Is Resolve compatibility required for the first shipped version, or is Final Cut Pro success enough to ship?
