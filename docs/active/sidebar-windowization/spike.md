---
doc-status: ready
---

# Sidebar Windowization Spike

## Overview

Hypnograph's current UI swings between a very clean viewer and a very dense embedded-sidebar mode. Windowizing the sidebars is meant to soften that split by turning the major control surfaces into optional AppKit windows that can stay out of the way until they are needed.

The spike outcome is mostly clear already. The project should move to four windows: `New Clips`, `Output Settings`, `Composition`, and `Effects`. `New Clips` and `Output Settings` come from the current left sidebar, while `Composition` and `Effects` come from the current right sidebar. This keeps the viewer central while separating setup tasks, composition controls, and effects work into clearer surfaces.

The intended behavior is AppKit-window based rather than a disguised SwiftUI panel system. Windows should be quickly showable and hideable, restorable across launches, and able to sit near the main window without being hard-docked to it. Clean-screen mode should hide them all and then restore the previous layout when clean-screen ends.

The main remaining uncertainty is not the overall direction but some implementation details: whether `Output Settings` and `New Clips` should stay separate immediately, how strong snapping behavior should be, what the default launch layout is, and whether opacity controls still feel worth carrying. Those are important, but they no longer need to block the project from being treated as an implementation track.

## Decision

- Replace embedded sidebars with four AppKit-managed windows: `New Clips`, `Output Settings`, `Composition`, and `Effects`.
- Keep the viewer central and avoid rebuilding a fixed all-controls frame elsewhere.
- Treat snapping as a helpful behavior, not as a docking commitment.
- Remove old sidebar-specific state and settings rather than preserving legacy placement or tab behavior.
- Continue from here as an implementation-and-stabilization project rather than as an open-ended spike.
