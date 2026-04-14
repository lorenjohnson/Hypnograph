---
doc-status: done
---

# Overview

Replace the current floating playbar/panel split with a bottom-mounted dock that becomes the primary time-based workspace for the app, and reshape the existing Composition/Output panels into a single contextual `Properties` panel.

The current app has too many overlapping panels, and the temporal surface is not yet the center of the experience. The intended change is:

- a bottom-mounted dock that stays attached to the main window
- a dock mode switch between `Sequence` and `Composition`
- a `Properties` panel with scope tabs `Sequence / Composition / Layer`

The dock becomes the place where time is manipulated, while `Properties` becomes the place where settings and effect chains for the current scope are edited. Renaming `sequence -> movie` and `composition -> scene` is explicitly out of scope for this project for now.

# Scope

- MUST replace the current floating playbar behavior with a bottom-mounted dock attached to the main window.
- MUST keep the dock focused on time-based interaction and transport.
- MUST support two dock modes: `Sequence` and `Composition`.
- MUST make `Sequence` mode show the sequence timeline across the full dock width.
- MUST make `Composition` mode show the current composition timeline and all layer timelines together.
- MUST move mute, solo, and visibility controls onto the layer timeline rows in `Composition` mode.
- MUST create a single `Properties` panel with internal scope tabs `Sequence`, `Composition`, and `Layer`.
- MUST move current Output Settings content into the `Sequence` scope of `Properties`.
- MUST move current composition-level settings into the `Composition` scope of `Properties`.
- SHOULD leave layer effect-chain editing de-emphasized or temporarily minimally surfaced rather than blocking the larger restructure.
- MUST NOT do the broader naming refactor in this project.

# Plan

- Smallest meaningful next slice:
  - Mount the current playbar to the bottom of the main window and introduce the `Sequence / Composition` dock mode switch without yet fully redesigning every row.
  - Replace the old `Composition` and `Output Settings` panel split with one `Properties` panel carrying `Sequence / Composition / Layer` tabs.
- Immediate acceptance check:
  - The dock is attached to the bottom of the Studio window rather than floating separately.
  - The dock can switch between `Sequence` and `Composition` modes.
  - The `Properties` panel exists and switches cleanly between `Sequence`, `Composition`, and `Layer`.
  - Existing sequence/composition settings remain editable through `Properties`.
- Follow-on slices:
  - Reintroduce and refine the sequence timeline in docked form.
  - Move layer timelines and quick controls into the `Composition` dock mode.
  - Finish moving quick layer controls and any remaining layer editing affordances into the new dock + `Properties` model.

# Open Questions

- Whether the dock should ever be detachable again after the first bottom-mounted pass.
- How much layer effect-chain editing should remain surfaced in the first `Layer` scope version versus deferred.
