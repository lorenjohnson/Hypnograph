---
created: 2026-01-24
updated: 2026-02-17
status: completed
completed: 2026-02-17
---

# Combine HUD into Player Settings

## Overview

Combine some/all of HUD view into the top of the Player Settings modal, possibly eliminating the HUD View entirely. Player Settings may get retitled. The combined view takes up more vertical space and anchors to top-left of screen.

## Current State

### HUDView contains:
- Module-specific HUD items (dynamic, from `dream.hudItems()`)
- Layers list with duration (e.g., "Layers (1:30)")
  - Each layer shows index and shortened file path
  - Current source highlighted in cyan
- Tooltip display section (contextual help)

### PlayerSettingsView contains:
- Title + close button
- Preview/Live mode toggle buttons
- Watch Mode toggle
- Max Layers stepper
- Clip Length Min/Max steppers
- Play Rate control (slider with turtle/rabbit buttons)
- Source Framing picker
- Aspect Ratio picker
- Transitions section (Style picker, Duration slider)
- Audio section (Preview/Live device pickers + volume sliders)

## Design Questions

- [ ] What from HUD is essential vs. just nice-to-have?
- [ ] Does the layers list belong in settings or is it more of a "current state" display?
- [ ] Should tooltips move into a status bar or disappear entirely?
- [ ] What should the combined panel be called? "Player Settings" feels wrong if it shows layers.
- [ ] How to handle the increased vertical space — scrollable? Collapsible sections?

## Possible Approaches

1. **Minimal merge**: Just add layers list to top of Player Settings, keep tooltips separate
2. **Full merge**: Everything in one panel, HUD view eliminated
3. **Redesign**: New panel design that organizes info vs. settings more clearly

## Notes

Files involved:
- [HUDView.swift](../../../Hypnograph/Views/HUDView.swift)
- [PlayerSettingsView.swift](../../../Hypnograph/Views/Components/PlayerSettingsView.swift)
