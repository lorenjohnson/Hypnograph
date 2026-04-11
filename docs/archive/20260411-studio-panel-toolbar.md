---
doc-status: done
---

# Overview

Add a docked Studio toolbar overlay at the top of the main window that gives fast, always-visible access to panel toggles and a shared panel transparency control.

This project started as a lightweight panel-toggle bar and ended up also carrying nearby cleanup that supported the same direction of travel: panel visibility controls in-window, clearer panel iconography, restored effects-library chain toggles, and a stronger top-level effect-target model that now includes the hypnogram/sequence level.

# Scope

- MUST render as an overlay attached to the Studio window, not as a layout region that changes player sizing.
- MUST expose the current Studio panel set as direct toggle buttons with labels that include the existing Option-number shortcuts.
- MUST include a single transparency slider that adjusts all Studio panels together.
- MUST apply that same shared transparency to the toolbar itself.
- MUST hide and show along with the rest of the panels/windows behavior already controlled by Studio.
- SHOULD reuse the existing Effects Composer top-bar and transparency interaction pattern where that keeps implementation simple.
- SHOULD keep the toolbar visually lightweight and obviously secondary to the media.
- MUST NOT redesign the existing panel host system as part of this slice.

# Outcome

- Added a top-mounted Studio toolbar overlay with icon-driven panel buttons and shared panel opacity.
- Centralized panel descriptors so the toolbar and Panels menu can share names/icons more honestly.
- Restored library-level enable/disable for effect chains and made disabled chains drop out of cycle/apply/random-generation paths.
- Added composition-level transition overrides with sequence defaults as fallback.
- Added a hypnogram-level effect chain in the model and renderer, with shared editing UI alongside sequence-level display settings.

# Notes

This project is complete enough to archive, but it also exposed the next structural step clearly: the bottom-docked playback/timeline workspace and a contextual `Properties` panel. That follow-on is now tracked separately.
