---
doc-status: draft
---

# Tighten Up Panel Design

## Overview

The Studio panels are functionally in a much better place now, but they still do not feel quite like one coherent design system. Labels, values, section headings, and grouped surfaces often compete at the same visual priority, which makes the windows feel more clamorous than they need to.

This project is not about a broad visual redesign. The goal is to make the existing panel system feel more unified through a small number of disciplined, incremental improvements that preserve what is already working.

The most important recommendation from the current design review is to standardize a shared "field row" pattern and apply it consistently. The base pattern should be:

- label on the left
- current value on the right
- control on its own line underneath
- predictable spacing before the next row

That pattern is already close to what works well in places like the `Composition` and `Output Settings` controls. The main opportunity is to make it the default everywhere instead of letting each panel improvise its own balance of headings, labels, values, and controls.

The next most valuable improvement is to strengthen visual hierarchy without adding much complexity:

- section headers should be a bit more separated from control rows
- row labels should be slightly quieter than they are now
- right-aligned values should feel consistently secondary
- grouped surfaces such as effect rows, source cards, and hypnogram cards should share more of the same radius, padding, and contrast language

If done well, this should make the panels feel more "of one system" without changing the current interaction model or creating design churn.

## Rules

- MUST treat this as an incremental design-system tightening pass, not a broad restyling project.
- MUST preserve the current interaction model and control behavior unless a specific improvement clearly supports clarity.
- MUST prioritize one shared field-row pattern across panel controls.
- MUST improve hierarchy through spacing, alignment, and contrast before introducing new decorative elements.
- SHOULD treat existing strong patterns in `Composition` and `Output Settings` as the main visual references.
- SHOULD unify grouped surfaces such as effect rows, source cards, and hypnogram cards where doing so reduces visual noise.
- MUST NOT let this project sprawl into a complete redesign of the Studio panel architecture.

## Plan

- Smallest meaningful next slice: define and implement one shared field-row pattern across a few representative panels so the hierarchy change can be judged in the real app.
- Immediate acceptance check: labels, values, controls, and section headers feel more distinct, and the panels read more calmly without losing density or utility.
- Follow-on slice: unify grouped-surface treatment across rows and cards so the major panel types feel like parts of the same system.

## Open Questions

- Which panels are the right first proving ground for the shared field-row pattern: `New Compositions`, `Output Settings`, `Sources`, or `Composition`?
- How much quieter should row labels become before the interface starts to lose too much energy or legibility?
- Which grouped surfaces most need unification first: effect rows, source cards, hypnogram cards, or layer rows?
