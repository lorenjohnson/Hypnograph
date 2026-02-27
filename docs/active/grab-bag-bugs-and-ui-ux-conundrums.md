---
created: 2026-02-27
updated: 2026-02-27
status: active
---

# Grab Bag: Bugs and UI/UX Conundrums

## Goal

Capture bug reports and UX/modeling conundrums as they come up, with enough detail to discuss, validate shared understanding, and either choose a fix path or log a proposed solution.

## Working Agreement

- Some items are discussion-first before implementation.
- Some items move directly to proposed solution + execution.
- Keep each item concrete: observed behavior, expected behavior, current model notes, and decision status.

## Items

## 1. Clip Length Model: Global Target vs Inferred Length

### Reported Behavior

- In the right sidebar Global section, changing `Clip Length` updates the global target duration.
- With multiple layers, extending global clip length does not automatically extend each layer's selected clip window.
- This feels awkward because you then have to manually extend individual layer windows in the clip trim strips.
- Conceptually, playback sometimes feels like it should just run for the longest layer window.

### Current Model (as implemented)

- Hypnogram has explicit `targetDuration` (global clip length).
- Layer trim UI currently caps each layer's selected duration against the global `targetDuration`.
- Composition and export build logic use explicit `targetDuration` as the rendered playback length.

### UX/Model Tension

- Explicit global duration gives predictable control.
- But it introduces duplicate interactions when users mentally model length as "the longest active layer."

### Candidate Direction (from discussion)

- Prototype a derived-length mode where effective clip length is inferred from layer windows (longest layer), rather than manually set as a separate global control.
- If we test this, we should also remove/adjust per-layer trim caps tied to global duration so layer edits are not blocked by current target length.

### Decision Status

- Open.
- Needs focused design + behavior pass before implementation.
