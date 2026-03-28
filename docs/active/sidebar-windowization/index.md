---
doc-status: ready
---

# Sidebar Windowization

## Overview

This project moves the current in-window SwiftUI sidebars into AppKit-managed windows that can be shown and hidden as needed. The point is to make Hypnograph less all-or-nothing: keep the viewer central, let control surfaces come and go more freely, and stop forcing composition work into one dense embedded frame.

The exploratory part of this project is mostly done. The current direction is to replace the embedded sidebars with four AppKit window surfaces: `New Clips`, `Output Settings`, `Composition`, and `Effects`. Those windows should support fast show/hide, persisted layout, clean-screen integration, and free positioning outside the main app bounds.

This entry file stays intentionally short. Spike conclusions live in [spike.md](./spike.md), and the implementation sequencing lives in [plan.md](./plan.md).

## Rules

- MUST replace the embedded SwiftUI sidebars with AppKit-managed windows.
- MUST keep current generation, composition, and effects behavior stable while moving surfaces.
- MUST support show/hide via menu or shortcut and persist window position, size, and visibility.
- MUST hide all floating windows in clean-screen mode and restore their prior visibility when clean-screen ends.
- MUST remove obsolete SwiftUI-sidebar settings, tab state, and open-state tracking once the new windows are in place.
- MUST NOT require migration work for old sidebar placement or open-tab settings.
- MUST NOT force hard docking; windows SHOULD remain moveable outside main-window bounds.
- SHOULD support edge-snapping behavior and optional opacity or translucency controls if they still feel useful after the basic move.

## Plan

Use [spike.md](./spike.md) as the decision record for why this project exists and what shape was chosen. Use [plan.md](./plan.md) for the implementation order, validation checklist, and remaining risks. The next work here should be execution and stabilization rather than reopening the basic window split unless something significant changes.
