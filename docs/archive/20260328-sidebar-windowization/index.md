---
doc-status: done
---

# Sidebar Windowization

## Overview

This project replaced the embedded SwiftUI sidebars with AppKit-managed Studio panels. The viewer stays central now, while `New Clips`, `Output Settings`, `Composition`, and `Effects` live in their own attached windows that can be shown and hidden independently.

The implementation uses AppKit child `NSPanel`s with persisted frame state, visibility restored through `WindowState`, and clean-screen integration driven by the same visibility model. `[` toggles `New Clips`, `]` toggles `Effects`, and the other two surfaces are available from the `View` menu.

The old embedded sidebars and their tab/open-state plumbing are gone. The result is simpler to reason about and leaves the Studio in the windowed direction this project was trying to validate.

## Notes

- Implemented as four attached AppKit panels: `New Clips`, `Output Settings`, `Composition`, and `Effects`.
- Persisted placement and visibility now comes from panel autosave plus `WindowState`, not old sidebar state.
- Clean-screen hides the panels and restores prior visibility on exit.
- First-launch defaults are intentionally generous: all four panels are shown until later UX tuning says otherwise.
- `Output Settings` and `Composition` do not have dedicated shortcuts yet.

## Review Notes

Questions worth a quick human pass:
- Should `Output Settings` and `Composition` get their own shortcuts now, or stay menu-only for the moment?
- Are the default panel positions and first-launch visibility too aggressive?
- Do we want snapping or translucency at all, or was the simpler panel model enough?
