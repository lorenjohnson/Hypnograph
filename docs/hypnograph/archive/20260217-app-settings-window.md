---
created: 2026-01-24
updated: 2026-02-17
status: completed
completed: 2026-02-17
---

# App Settings Window

## Overview

Determine what app-wide settings exist, which are already exposed in the UI, and whether a dedicated Settings window (Preferences) is needed.

## Current Settings (from Settings.swift)

### Exposed Elsewhere
- `sourceMediaTypes` — Images/Videos toggles in Sources menu
- `activeLibraries` — Source library selection in Sources menu
- `effectsListCollapsed` — Effects Editor UI state (auto-saved)
- `outputResolution` — Output Resolution submenu in Composition menu

## Questions to Answer

- [ ] Should unexposed settings get a UI, or is settings.json fine for power users?
- [ ] Is a separate Settings window needed, or can these live in PlayerSettingsView?
- [ ] What new settings might users want?
  - [ ] Default aspect ratio for new hypnograms?
  - [ ] Auto-save to Photos after render?
  - [ ] Keyboard shortcut customization?
  - [ ] Effect chain default behavior?

### Storage Location Decision

Consider changing the default storage location from `~/Library/Application Support/Hypnograph/recipes` to `~/Movies/Hypnograph`. This affects where hypnogram files (.hypnogram) are saved.

- [ ] Should this be a hardcoded change or a user setting?
- [ ] If user setting, expose in Settings window
- [ ] Migration path for existing users with recipes in the old location?

## Possible Approaches

1. **No Settings window** — Keep things simple, power users edit JSON
2. **Minimal Settings window** — Just the truly app-wide stuff (folders, history limit)
3. **Full Preferences pane** — macOS-style Settings with tabs for different categories

## Notes

The "Show Settings Folder" command in the Hypnograph menu already helps users find settings.json. A Settings window would be more discoverable but adds UI surface area to maintain.

## Completion Notes

Implemented a dedicated app settings surface and exposed key app-wide controls in UI:
- render output folder chooser
- history limit control
- clip-history clear action
- keyboard accessibility override toggle
- live/performance mode options toggle

Files involved:
- [Settings.swift](../../../Hypnograph/Settings.swift) — Settings struct definition
- [SettingsStore.swift](../../../Hypnograph/SettingsStore.swift) — Persistence layer
