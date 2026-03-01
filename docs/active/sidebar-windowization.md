---
created: 2026-03-01
updated: 2026-03-01
status: active
---

# Sidebar Windowization

## Overview

Move current in-window SwiftUI sidebars into AppKit-managed windows that can be shown/hidden as needed.

This project is intentionally valuable on its own even if the full rewrite is deferred, and by project completion there should be no SwiftUI sidebars left.

## Related Direction

This project is a likely first move for the broader backlog concept:
- [composition-timeline-pivot-spike](../backlog/composition-timeline-pivot-spike.md)

This work should remain compatible with that larger direction but avoid requiring full architecture replacement up front.

## Why this first

Current UI alternates between:
- very clean screen (few controls)
- very dense/full-control mode

Windowizing sidebars should make control surfaces more flexible and less all-or-nothing:
- open only what is needed
- keep optional panels out of the way most of the time
- preserve composition visibility while accessing controls

## Goal

Replace embedded left/right SwiftUI sidebars with four AppKit window surfaces while keeping current underlying behavior largely intact.

## Proposed Window Split

### 1) New Clips window (from left sidebar)

Primary contents:
- new/random clip generation parameters
- source selection controls

Likely UI shape:
- two tabs inside one window:
1. `New Clips`
2. `Sources`

### 2) Output Settings window (from left sidebar)

Primary contents:
- output/display/render-related settings currently living in left-side controls

Intent:
- this window is optional most of the time
- can stay closed during normal composition sessions

### 3) Composition window (from right sidebar)

Primary contents:
- current right-sidebar composition controls

Notes:
- aligns with separating composition tasks from effect-chain tasks

### 4) Effects window (from right sidebar)

Primary contents:
- current right-sidebar effects controls

## Window Behavior Requirements

- AppKit windows (not pure SwiftUI panel behavior)
- can sit snapped to main window edges but are not hard-docked
- can be moved outside the main window bounds
- can be shown/hidden quickly via menu/shortcut
- should support opacity/translucency control where useful (especially overlay usage)
- persist window state (position, size, visibility, opacity if implemented)
- clean-screen mode hides all windows, including floating windows
- leaving clean-screen mode restores previous window visibility and placements

## Settings Cleanup Requirements

- no migration work is required for previous sidebar placement/open-tab settings
- remove prior SwiftUI-sidebar state settings and tracking
- remove previous tab/open-state clutter that only existed for embedded sidebars

## Scope

### In scope

- Window host/scaffolding for the four surfaces
- Move existing sidebar controls into new windows with minimal behavior change
- Show/hide commands and state persistence
- Basic snap-to-edge behavior (or implementation-ready scaffolding if full snapping is staged)
- clean-screen visibility integration for all window surfaces
- cleanup/removal of obsolete SwiftUI-sidebar settings state

### Out of scope

- timeline/NLE model redesign
- compound clip model redesign
- full Effects Studio product split
- major effect-chain model changes/renaming
- major visual redesign of individual controls

## UX Intent

- make Hypnograph feel less fixed/hardened in one frame
- keep composition/viewer central
- reduce panel clutter by allowing context-specific windows
- preserve fast toggling between minimal and advanced operation

## Technical Approach (initial)

### Step 1: Window infrastructure

- add AppKit window controller management for four surfaces
- define stable identifiers and restore/save hooks
- add menu actions for toggling each window

### Step 2: Left sidebar extraction

- migrate `new clip` + `source selection` controls into `New Clips`
- migrate output/display/render controls into `Output Settings`
- preserve existing state wiring

### Step 3: Right sidebar extraction

- migrate current right-side sections into two windows:
  - `Composition`
  - `Effects`
- preserve existing chain/effect behavior

### Step 4: Clean-screen + restoration behavior

- enforce: clean-screen hides all windows
- restore pre-clean-screen window visibility and placement when clean-screen exits
- avoid losing user layout choices while toggling clean-screen

### Step 5: Snap + free movement behavior

- implement edge-snapping behavior against main window (if near edge)
- maintain free drag outside main-window bounds
- ensure no forced docking

### Step 6: Settings cleanup + stabilization

- remove obsolete SwiftUI-sidebar settings state and tab/open tracking
- verify no regressions in current composition flow
- tune default window layouts and visibility behavior
- document keyboard/menu control map

## Verification Checklist

- [ ] Main window works with sidebars hidden and windows closed
- [ ] `New Clips` window can be opened/closed and functions as current left controls
- [ ] `Output Settings` window can be opened/closed and settings apply correctly
- [ ] `Composition` window maps to current composition controls
- [ ] `Effects` window maps to current effects controls
- [ ] Windows can move outside main app bounds
- [ ] Window positions/visibility restore correctly after relaunch
- [ ] clean-screen hides all windows
- [ ] leaving clean-screen restores previous window visibility + placement
- [ ] obsolete SwiftUI-sidebar settings/state keys are removed
- [ ] No regressions to random clip generation/source filtering/effects application

## Risks

- Window lifecycle/state sync complexity
- Focus/keyboard routing bugs when multiple windows are active
- Duplicate ownership during migration if old sidebar paths are not fully retired
- Snap behavior edge cases (multi-monitor setups, fullscreen transitions)

## Open Questions

1. Should snap behavior be magnetic only (temporary) or persistent docking mode?
2. Should `Output Settings` and `New Clips` remain separate windows in v1, or merge initially and split later?
3. Should `Composition` and `Effects` allow independent opacity controls?
4. What is the default launch layout (which windows open by default)?
5. Should window snapping differ across normal vs fullscreen modes?

## Deliverable

A production-usable AppKit windowized control-surface system replacing embedded sidebars, with minimal feature regression and clear upgrade path to the broader composition-first rewrite.
