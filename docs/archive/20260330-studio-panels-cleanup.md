---
doc-status: done
---

# Studio Panels Cleanup

**Created:** 2026-03-29
**Updated:** 2026-03-30

## Outcome

This cleanup pass is complete.

It delivered:
- the launch and auto-hide cleanup for Studio panels
- removal of the old clean-screen instructional HUD
- migration of the Hypnograms list into the shared Studio panel system
- the final play bar resize fix so layer-driven height changes no longer ratchet the panel upward
- a play bar interaction fix so the volume slider no longer drags the whole window

## Notes

The key final technical fix was treating `playerControls` as not needing the extra fixed-height padding used by the other hosted panels, while also disabling background-window dragging for that panel so its controls could receive drag gestures reliably.
