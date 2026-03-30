---
doc-status: completed
---

# Composition Timeline and Length

## Overview

This project started as a broader spike about composition-level timing and editing. The main answer that emerged was much simpler than the original framing: authored `Composition Length` did not need to remain a separate control. The effective duration of a composition is now derived from the longest current layer trim, while `Composition Length (Range)` remains only as a generation-time default in `New Compositions`.

That simplification removed a redundant control path and made composition behavior line up more directly with the per-layer trim model already present in the play bar. The project also absorbed a few closely related cleanup items while the area was open, including removing the old play-bar speed dropdown, preventing render from auto-advancing away from the current composition, and tightening the history-position HUD so it only appears for actual history navigation rather than flashing when a new live-end composition is generated.

This project is complete enough to archive. The remaining composition-timeline work is a follow-on UI design problem rather than an unresolved model spike.

## Rules

- MUST treat composition duration as derived from the longest current layer trim rather than as a separately authored value.
- MUST keep `Composition Length (Range)` in `New Compositions` as a generation-time default, not as an authored composition control.
- MUST keep this work focused on single-composition timing semantics and nearby cleanup, not on multi-composition sequencing.
- SHOULD make composition-level timing behavior more legible in the UI as a follow-on, especially around playhead visibility and composition-level selection.
- MUST NOT reintroduce a separate authored composition-length control unless there is a clear new product reason.

## Plan

- Smallest meaningful current slice: remove the authored `Composition Length` control and derive effective composition duration from the longest current layer trim while preserving generation-time clip-length defaults for new hypnograms.
- Immediate acceptance check: trimming a layer longer or shorter changes effective composition duration automatically, and no separate composition-length control remains in the Composition window.
- Follow-on slice: design a composition timeline above the layer timelines with a visible playhead and clearer composition-level selection affordances.

## Open Questions

- What is the clearest first indication that the composition itself is selected, especially when no layer is selected and the operator is editing composition-level settings?
- Should scrubbing ultimately live on the composition timeline, the layer timelines, or both once that follow-on UI pass begins?
