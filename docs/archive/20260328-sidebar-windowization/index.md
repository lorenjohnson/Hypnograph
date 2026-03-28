---
doc-status: done
---

# Sidebar Windowization

## Overview

This project replaced the embedded SwiftUI sidebars with AppKit-managed Studio windows. The viewer stays central while `New Clips`, `Output Settings`, `Composition`, and `Effects` live in their own attached windows that can be shown and hidden independently.

The implementation now uses a Studio-local `WindowStateController` plus a `WindowHostService`. The controller owns visibility, clean-screen semantics, and persistence; the host owns actual AppKit window creation, positioning, and show/hide behavior. `[` toggles `New Clips`, `]` toggles `Effects`, and the other two surfaces are available from the `View` menu.

The old embedded sidebars and their tab/open-state plumbing are gone. The window system is now stable enough for this pass: close/hide state is preserved, clean-screen restores correctly, clip changes no longer resurrect hidden windows, and the smaller utility-window chrome is in place.

## Notes

- Implemented as four attached AppKit panels: `New Clips`, `Output Settings`, `Composition`, and `Effects`.
- Persisted placement and visibility now comes from a Studio-local window controller plus window autosave, not old sidebar state.
- Clean-screen hides the panels and restores prior visibility on exit.
- First-launch defaults are intentionally generous: all four panels are shown until later UX tuning says otherwise.
- `Output Settings` and `Composition` do not have dedicated shortcuts yet.
- Temporary `[` / `]` window shortcuts were removed so the Studio no longer implies a left/right panel model.
- The current window chrome uses utility-window styling with a lightweight native title accessory label.

## Notes

Remaining questions for a later pass:
- whether the Studio should eventually support a docked/internal panel mode in addition to floating windows
- whether `Output Settings` and `Composition` should get dedicated shortcuts once the longer-term window model is clearer
