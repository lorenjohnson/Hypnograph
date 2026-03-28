---
doc-status: done
---

# Sidebar Windowization Plan

## Plan

1. Built AppKit panel hosting for the four Studio surfaces.
2. Extracted `New Clips`, `Output Settings`, `Composition`, and `Effects` into their own window views.
3. Rewired menu actions, keyboard shortcuts, clean-screen behavior, and persisted layout around the new panels.
4. Removed the embedded sidebar views and their old tab/open-state ownership.
5. Verified the Studio still works with the panels closed and that the new window model builds cleanly.
6. Extracted a Studio-local `WindowStateController` so visibility, clean-screen semantics, and persistence no longer live in `HypnographState`.
7. Reduced the AppKit side to a `WindowHostService` that only hosts and syncs Studio windows.
8. Refined window behavior around sizing, closeability, restore semantics, and utility-window chrome until the model felt solid.

Validation:
- Main window works with all panels closed.
- `New Clips`, `Output Settings`, `Composition`, and `Effects` map correctly to the old sidebar behavior.
- Clean-screen hides and restores panel visibility correctly.
- Hidden windows stay hidden across clip recomposition and loop restart.
- Window positions persist via autosave names.
- No build regressions were introduced by the surface move.
- Closing individual panels updates the saved visible-set correctly.
- Smaller panels fit their content height cleanly instead of opening short.
- Window chrome now reads more like internal Studio tool windows than generic app windows.

Risks:
- Default layout and shortcut coverage may still want a small UX pass.
- Snapping and translucency were intentionally left out of the first pass.
- A future docked/internal panel mode may want a different host model than the current floating-window implementation.
