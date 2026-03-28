---
doc-status: ready
---

# Sidebar Windowization Plan

## Plan

1. Build the AppKit window infrastructure.
   - Add controller and lifecycle management for the four target windows.
   - Define stable identifiers plus restore and save hooks.
   - Add menu actions and shortcuts for toggling each window.
2. Extract the left sidebar into `New Clips` and `Output Settings`.
   - Move random clip generation and source-selection controls into `New Clips`.
   - Move output, display, and render controls into `Output Settings`.
   - Preserve the current underlying state wiring while the surfaces move.
3. Extract the right sidebar into `Composition` and `Effects`.
   - Move current composition controls into `Composition`.
   - Move current chain and effect controls into `Effects`.
   - Keep current editing behavior stable during the split.
4. Add clean-screen and restoration behavior.
   - Hide all floating windows when clean-screen is enabled.
   - Restore the prior visibility and placement state when clean-screen is disabled.
   - Avoid losing user layout choices during toggling.
5. Add snapping, free movement, and layout polish.
   - Support magnetic edge behavior against the main window if it still feels useful.
   - Keep free dragging outside the main app bounds.
   - Tune default positions and launch behavior.
6. Remove sidebar-era state and stabilize.
   - Delete obsolete SwiftUI sidebar settings, tab state, and open-state tracking.
   - Verify there is no duplicate ownership between old and new surfaces.
   - Document the resulting menu and keyboard control map if needed.

Validation:
- Main window still works with all windows closed.
- `New Clips`, `Output Settings`, `Composition`, and `Effects` all map correctly to current behavior.
- Window positions and visibility restore correctly after relaunch.
- Clean-screen hides and restores all windows correctly.
- No regressions appear in random clip generation, source filtering, composition editing, or effects application.

Risks:
- Window lifecycle and focus routing bugs.
- Duplicate ownership during migration if old sidebar paths linger.
- Snap behavior edge cases across fullscreen or multi-monitor setups.
- Excess polish work distracting from the basic surface move.
