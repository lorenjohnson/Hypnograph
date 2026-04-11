---
doc-status: in-progress
---

# Overview

Add a docked Studio toolbar overlay at the top of the main window that gives fast, always-visible access to panel toggles and a shared panel transparency control.

Right now panel visibility is mostly controlled from keyboard shortcuts and the menu bar. That works once the shortcuts are memorized, but it is not a great control surface while actively using the app. The intended change is a lightweight overlay toolbar that stays attached to the Studio window, overlaps the video instead of resizing it, and exposes the current panel set as direct push-button toggles labeled with their existing Option-number shortcuts.

The toolbar should also include a single transparency slider for all Studio panels, following the Effects Composer pattern closely enough that it feels familiar and low-risk.

# Scope

- MUST render as an overlay attached to the Studio window, not as a layout region that changes player sizing.
- MUST expose the current Studio panel set as direct toggle buttons with labels that include the existing Option-number shortcuts.
- MUST include a single transparency slider that adjusts all Studio panels together.
- MUST apply that same shared transparency to the toolbar itself.
- MUST hide and show along with the rest of the panels/windows behavior already controlled by Studio.
- SHOULD reuse the existing Effects Composer top-bar and transparency interaction pattern where that keeps implementation simple.
- SHOULD keep the toolbar visually lightweight and obviously secondary to the media.
- MUST NOT redesign the existing panel host system as part of this slice.
- MUST NOT change the existing panel shortcut assignments in this slice.

# Plan

- Smallest meaningful next slice:
  - Add a top overlay Studio toolbar with panel toggle buttons and shortcut labels, plus a shared panel-opacity slider.
  - Thread one shared opacity value through the Studio panel presentation path and the toolbar overlay.
- Immediate acceptance check:
  - The toolbar appears over the Studio window without resizing the player.
  - Clicking a toolbar button toggles the matching panel.
  - The button labels match the existing Option-number shortcuts.
  - Moving the slider fades all Studio panels and the toolbar together.
  - Hiding panels hides the toolbar too.

# Open Questions

- Whether the shared opacity should persist in Studio settings immediately, or start as session-only until the interaction feels right.
- Whether the toolbar should include only the current primary panels, or also live-display controls later.
