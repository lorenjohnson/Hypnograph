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

## Active Items

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

## 22. Layout Transforms vs Viewer Pan/Zoom (Two Distinct Interaction Modes)

### Requested Feature Set

- There are two related but distinct capabilities to add:
  - Composition editing transforms (per-layer layout)
  - Playback viewer navigation (temporary pan/zoom on the rendered view)

### A) Composition Editing: Per-Layer Layout Controls

Desired capabilities for each layer in a composition:
- Position
- Resize / scale
- Crop
- Zoom (as part of transform workflow)

Notes:
- This is authoring behavior that should persist as part of the composition.
- Likely needs an explicit edit mode (or similar guardrail) so playback interactions are not accidentally interpreted as layout edits.

### B) Viewer Navigation: Playback-Time Pan/Zoom

Desired capabilities while viewing playback (including paused view):
- Zoom in/out of the current rendered hypnogram
- Pan with hand tool / drag
- Quick reset back to normal screen framing at any time

Notes:
- This is viewport/navigation behavior, not composition mutation.
- Should be kept distinct from per-layer transform editing to avoid model confusion.

### Design Tension / Open Question

- Interaction model should make mode boundary clear:
  - default playback mode vs transform-edit mode
  - avoid accidental edits while navigating playback view

### Decision Status

- Open feature design item.
- Needs focused design + behavior pass before implementation.

## 10. Recents/Favorites ("Hypnograms" Window) Relevance and Model Clarity

### Reported Behavior / Concerns

- Current window feels visually old-style and can appear under/behind left sidebar.
- Unclear mental model of what appears there and why.
- Tension between portable `.hypno` files and "favorites/recents" as app-managed records.
- Unclear whether current favorite storage semantics are ideal long-term.

### Product Direction Context

- Future sets/timeline workflows may supersede or reshape this surface.
- Interim question: keep and improve now vs temporarily reduce/retire until better integrated replacement exists.

### Decision Status

- Open product/UX direction item.

## 11. Save Semantics for Hypnogram Files

### Reported Behavior

- Repeated Save currently tends to produce new uniquely named files.

### Expected Behavior

- Save should overwrite the last saved file for that working hypnogram/session (normal document-app behavior).
- Save As should create/select a new file target and then become the active save target.

### Notes

- Existing UUIDs in model may support tracking working identity, but file-target ownership semantics still need explicit design.

### Decision Status

- Open.

## 16. History Semantics When Creating New Hypnogram Mid-History

### Reported Behavior / Uncertainty

- When user is in the middle of history and creates a new hypnogram, behavior is unclear in UX (likely insert-at-current-index behavior).
- User expectation may instead be: jump to end of history and create the new item there.
- Current history navigation is valuable and fun; preserving that feel is important.

### Related Model/UX Questions

- Should history always behave as append-only at the end (with cap trimming oldest), regardless of current position?
- With capped history (default 200), should new creation always push/drop at one edge predictably?
- What should UI numbering communicate:
  - current physical index in stored buffer
  - or user-facing recency order
- Navigation intuition question:
  - going "back" from latest feeling like 200 -> 199 -> 198 may be intuitive,
  - but it may obscure whether user is currently at newest vs middle.

### Desired Outcome

- Define clear semantic rule for new-creation while browsing older history.
- Improve HUD/indicator UX so "you are at latest" vs "you are in past history" is obvious without mental bookkeeping.

### Decision Status

- Open.

## 17. Play Rate vs History Playback Speed: Overlap and Precedence Confusion

### Reported Behavior / Uncertainty

- There appears to be conceptual and/or behavioral duplication between:
  - global/per-clip `playRate`
  - `history playback speed` control on playback UI
- It is unclear whether history playback speed is overriding play rate more broadly than intended.
- It is also unclear what happens when playback transitions from older history into newly generated clips:
  - does history speed still apply
  - or does generated clip playRate take over

### Why This Feels Risky

- Two similar controls with unclear precedence create mental-model friction.
- Even if implementation is internally correct, current UX does not make control scope obvious.

### Candidate Direction

- Likely simplify by removing `history playback speed` for now and relying on existing play-rate controls.
- If retained, explicitly define and surface precedence/scope in UI and docs.

### Decision Status

- Open.

## Completed Items (Moved Out of Active Focus)

### 2026-02-27 Batch: Five Small High-Value Fixes

- `#3` chain context menu: removed no-op `Load from Library...` action.
- `#15` clip trim strips: tightened handle-grab behavior so short windows can be moved without accidentally grabbing trim handles.
- `#18` Effects Studio param definitions: removed technical preamble from the top of the panel.
- `#19` Effects Studio param definitions: adding a param now auto-scrolls to the new row.
- `#21` Effects Studio header: removed `Refresh` button; no file watching was added.

### 2026-02-27 Batch: Next Small High-Value Fixes

- `#3` composition/global chain UX: `Add Effect` now includes `Effect Chains` + `FX` sections, so existing chains can be applied directly without tab switching.
- `#7` player controls bar: now uses inactivity auto-hide outside clean-screen mode too.
- `#12` Effects Studio access: removed top-level `Studio` menu, moved open action into app-menu area, and added `Enable Effects Studio` feature flag in Settings.
- `#14` chain context menu: `Save as New Template...` now generates unique macOS-style names (`Name`, `Name (1)`, ...).
- `#20` Effects Studio header: replaced runtime-effect picker presentation with a flush-left anchored menu control.

### 2026-02-27 Batch: Next Five (Buttons + Parameter Controls)

- `#2` chain editing in composition/global path: added drag-and-drop effect reordering within the chain (removed arrow reorder controls).
- `#5` display/source framing: replaced dropdowns with direct `Fit` / `Fill` button controls.
- `#6` aspect ratio quick-select: replaced dropdowns with direct preset ratio buttons.
- `#8` defaults controls in Main: added per-parameter reset-to-default buttons plus effect-level reset controls.
- `#9` randomization: added randomize-parameters actions at both effect-level and chain-level (excluding `opacity` in first pass).

### 2026-02-27 Batch: Keyboard + Audio + Shared Controls

- `#4` keyboard override stability: fixed shortcut handling after Effects Chain tab roundtrip by switching shortcut gating to active text-responder detection.
- `#13` layer audio controls: added per-layer `M` mute toggle beside `S` in composition rows, including red active state.
- Main + Effects Studio parameter UI: both now use the same shared `EffectParameterRowView` control path to avoid behavior drift.
