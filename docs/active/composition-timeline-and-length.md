---
doc-status: draft
---

# Composition Timeline and Length

## Overview

This project is about editing a single authored composition. In the actual UI today, that means the `Composition Length` control in the Composition window and the per-layer in or out ranges shown in the play bar. It is separate from the `New Compositions` defaults window, which is about generation settings for future compositions.

The immediate friction is that composition length and per-layer in or out sizing feel too disjointed. The operator can change `Composition Length` in one place and trim individual layers in another, but the relationship between them is not clear enough in the editing surface itself.

The current direction is to add a composition timeline above the layer timelines in the play bar, using the same general visual and interaction language as the existing layer timeline controls. That surface should make overall composition duration legible and editable in one place instead of forcing the operator to mentally reconcile the Composition window slider with separate per-layer trim ranges.

This project also likely needs a visible playhead across the composition timeline and layer timelines so the current playback position is legible while a composition is running. Scrubbing is probably part of the same interaction family, though the exact scope still needs to be decided.

While this project is focused on composition-level editing, it also needs to resolve a nearby clarity issue in the same UI surface: it is not currently clear enough when the composition itself is selected versus when an individual layer is selected, nor is the composition-level selection state indicated strongly enough once it has been selected. That should be resolved as part of this work rather than left as a separate loose issue.

This should remain a spike for now. There is enough product direction to open the project, but important behavior questions remain unresolved, especially around how changing composition length should propagate to the layers and how that interacts with shorter source clips.

## Rules

- MUST keep this project focused on timeline editing and playback visibility within a single composition, not on multi-hypnogram sequencing or history authoring.
- MUST treat this work as separate from [Sequences](/Users/lorenjohnson/dev/Hypnograph/docs/active/sequences.md), even if the visual language ends up related.
- MUST explore adding a composition timeline above the existing layer timelines in the play bar.
- SHOULD reuse the same or very similar control language as the current layer timelines rather than inventing a disconnected timeline UI.
- MUST clarify how composition length edits affect underlying layer trim ranges.
- MUST make composition-level selection clearer, both in how the operator selects the composition and in how the selected state is visually indicated.
- SHOULD include a visible playhead for the composition and layers if that remains the clearest way to make playback position legible.
- MAY include scrubbing in the same project if it remains tightly coupled to the playhead and composition timeline model.
- MUST NOT treat the unresolved propagation rules as settled before the spike work is done.

## Plan

- Smallest meaningful next slice: describe the current single-composition editing contract in plain language, including what `Composition Length` currently does in the Composition window, how layer trim ranges relate to it, and where the present friction actually comes from in editing.
- Immediate acceptance check: the project should leave behind a clearer model of what a composition timeline is responsible for, how composition-level selection is surfaced, and a concrete recommendation for the first UI prototype.
- Follow-on slice: prototype a composition timeline above the layer timelines with a visible playhead, then evaluate whether composition-length edits should clamp, extend, or otherwise transform the layer ranges while also clarifying composition selection in the Composition window.

## Open Questions

- When composition length is shortened, should all layer ranges be automatically reduced to fit, or are there cases where that should be more selective?
- When composition length becomes longer than one or more source clips, should those layers extend automatically, loop, hold, or remain shorter than the composition?
- Should scrubbing be allowed from any layer timeline, only from the composition timeline, or both?
- What is the clearest first indication that the composition itself is selected, especially when no layer is selected and the operator is editing composition-level settings?
