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

Validation:
- Main window works with all panels closed.
- `New Clips`, `Output Settings`, `Composition`, and `Effects` map correctly to the old sidebar behavior.
- Clean-screen hides and restores panel visibility correctly.
- Window positions persist via autosave names.
- No build regressions were introduced by the surface move.

Risks:
- Default layout and shortcut coverage may still want a small UX pass.
- Snapping and translucency were intentionally left out of the first pass.
