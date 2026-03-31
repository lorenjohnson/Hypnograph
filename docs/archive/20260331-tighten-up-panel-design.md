---
doc-status: completed
---

# Tighten Up Panel Design

## Overview

The Studio panels are functionally in a much better place now, but they still do not feel quite like one coherent design system. Labels, values, section headings, and grouped surfaces often compete at the same visual priority, which makes the windows feel more clamorous than they need to.

This project was not about a broad visual redesign. The goal was to make the existing panel system feel more unified through a small number of disciplined, incremental improvements that preserve what was already working.

The central direction was to standardize a shared field-row pattern and apply it consistently. The base pattern was:

- label on the left
- current value on the right
- control on its own line underneath
- predictable spacing before the next row

That pattern now anchors key panel controls and has reduced the sense that each panel is improvising its own balance of labels, values, and controls.

## Outcome

This pass delivered:

- a shared field-row pattern for Studio panel controls
- calmer slider rows and tighter parameter spacing in dense editors
- improved separation between primary labels and tertiary metadata
- cleaner stepped-slider tick marks
- a simpler panel-hide interaction model:
  - clicking the player background toggles panels
  - `Tab` toggles panels
  - auto-hide now only controls whether visible panels hide again after inactivity
- View-menu support for `Hide Panels` as a real checked toggle
- `Hypnograms` added to the Studio Panels list in the View menu

The panels still have room for more visual tightening, especially around nested object-card hierarchy, but this pass established a clearer shared structure without destabilizing the current interaction model.

## Rules

- MUST treat this as an incremental design-system tightening pass, not a broad restyling project.
- MUST preserve the current interaction model and control behavior unless a specific improvement clearly supports clarity.
- MUST prioritize one shared field-row pattern across panel controls.
- MUST improve hierarchy through spacing, alignment, and contrast before introducing new decorative elements.
- SHOULD treat existing strong patterns in `Composition` and `Output Settings` as the main visual references.
- SHOULD unify grouped surfaces such as effect rows, source cards, and hypnogram cards where doing so reduces visual noise.
- MUST NOT let this project sprawl into a complete redesign of the Studio panel architecture.

## Completion Note

This project is complete enough to archive. Any further tightening should likely happen as smaller follow-on passes around specific dense areas, especially nested effect/object cards and grouped-surface hierarchy.
