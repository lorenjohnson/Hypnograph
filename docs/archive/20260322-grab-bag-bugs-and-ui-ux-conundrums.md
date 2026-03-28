---
doc-status: done
---

# Grab Bag: Bugs and UI/UX Conundrums

**Created:** 2026-02-27
**Updated:** 2026-03-22

## Archive Note

This document now captures only completed items from the original active grab-bag project.
On 2026-03-22, unfinished items were split into dedicated active project docs.

## Completed Items

### 2026-02-27 Batch: Five Small High-Value Fixes

- `#3` chain context menu: removed no-op `Load from Library...` action.
- `#15` clip trim strips: tightened handle-grab behavior so short windows can be moved without accidentally grabbing trim handles.
- `#18` Effects Composer param definitions: removed technical preamble from the top of the panel.
- `#19` Effects Composer param definitions: adding a param now auto-scrolls to the new row.
- `#21` Effects Composer header: removed `Refresh` button; no file watching was added.

### 2026-02-27 Batch: Next Small High-Value Fixes

- `#3` composition/global chain UX: `Add Effect` now includes `Effect Chains` + `FX` sections, so existing chains can be applied directly without tab switching.
- `#7` player controls bar: now uses inactivity auto-hide outside clean-screen mode too.
- `#12` Effects Composer access: removed top-level `Studio` menu, moved open action into app-menu area, and added `Enable Effects Composer` feature flag in Settings.
- `#14` chain context menu: `Save as New Template...` now generates unique macOS-style names (`Name`, `Name (1)`, ...).
- `#20` Effects Composer header: replaced runtime-effect picker presentation with a flush-left anchored menu control.

### 2026-02-27 Batch: Next Five (Buttons + Parameter Controls)

- `#2` chain editing in composition/global path: added drag-and-drop effect reordering within the chain (removed arrow reorder controls).
- `#5` display/source framing: replaced dropdowns with direct `Fit` / `Fill` button controls.
- `#6` aspect ratio quick-select: replaced dropdowns with direct preset ratio buttons.
- `#8` defaults controls in Main: added per-parameter reset-to-default buttons plus effect-level reset controls.
- `#9` randomization: added randomize-parameters actions at both effect-level and chain-level (excluding `opacity` in first pass).

### 2026-02-27 Batch: Keyboard + Audio + Shared Controls

- `#4` keyboard override stability: fixed shortcut handling after Effects Chain tab roundtrip by switching shortcut gating to active text-responder detection.
- `#13` layer audio controls: added per-layer `M` mute toggle beside `S` in composition rows, including red active state.
- Main + Effects Composer parameter UI: both now use the same shared `EffectParameterRowView` control path to avoid behavior drift.
