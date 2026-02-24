---
created: 2026-01-24
updated: 2026-02-17
status: completed
completed: 2026-02-17
---

# Command Menu Review

## Overview

Review and update command menus to ensure they make sense. Some existential questions to answer: do we still have an "add layer" command on "."? What commands should exist and where?

## Current Menu Structure

### Hypnograph Menu (App Menu)
- Play/Pause — `Space`
- Clear Clip History
- Show Settings Folder
- Install hypnograph CLI and Finder Action

### File Menu
- New — `Cmd+N`
- Save Hypnogram — `Cmd+S`
- Save Hypnogram As… — `Cmd+Shift+S`
- Save and Render — `Cmd+Option+S`
- Open Hypnogram… — `Cmd+O`

### View Menu
**Overlays:**
- Info HUD — `I`
- Effects Editor — `E`
- Hypnogram List — `H`
- Clean Screen — `Tab`

**Player:**
- Player Settings — `P`
- Watch — `W`

**Live Display:**
- Live Preview — `L`
- Live Mode — `Cmd+L`
- External Monitor — `Cmd+Shift+L`
- Send to Live Display — `Cmd+Return`
- Reset Live Display — `Cmd+Shift+R`

**Bottom:**
- Full Screen — `Ctrl+Cmd+F`

### Sources Menu
- Images — Toggle
- Videos — Toggle
- Apple Photos (All Photos, Custom Selection `Cmd+Shift+O`, dynamic library items)
- Folders (dynamic folder items)

### Composition Menu
- Toggle Live Mode (Preview/Live)
- Cycle Effect Forward — `Cmd+E`
- Cycle Effect Backward — `Cmd+Shift+E`
- Add Source — `Shift+N`
- Next/Previous Clip — `→` / `←` (when Effects Editor closed)
- Next/Previous Source — `Option+→` / `Option+←` (when Effects Editor closed)
- Select Source 1-9 — `1-9`
- Select Global Layer — `` ` ``
- Clear Current Layer Effect — `C`
- Clear All Effects — `Ctrl+Shift+C`
- New Clip — `N`
- Delete Clip — `Cmd+Delete`
- Save Hypnogram — `Cmd+S`
- Render Video
- Favorite Hypnogram — `Cmd+F`
- Aspect Ratio submenu
- Output Resolution submenu

### Source Menu
- Cycle Blend Mode — `M`
- New Random Clip — `.`
- Delete Source — `Delete`
- Add to Exclude List — `Shift+X`
- Add to Favorites — `Shift+F`

### Special Keyboard Handling (NSEvent)
- Tab — Toggle Clean Screen
- Backtick hold — Suspend global effects temporarily
- 1-9 hold — Solo mode for source (double-tap to latch)

## Questions to Answer

- [ ] Is "Add Source" (`Shift+N`) vs "New Random Clip" (`.`) confusing? What's the difference?
- [ ] Should "New Clip" (`N`) exist separately from "Add Source"?
- [ ] Is the Composition vs Source menu split intuitive?
- [ ] Are there redundant commands (Save Hypnogram appears in File and Composition)?
- [ ] What commands are never used and could be removed?
- [ ] Should game controller mapping be removed entirely? (separate decision)

## Notes

Menu structure is defined in:
- [AppCommands.swift](../../../Hypnograph/AppCommands.swift)
- [DreamMenus.swift](../../../Hypnograph/DreamMenus.swift) — compositionMenu(), sourceMenu()
