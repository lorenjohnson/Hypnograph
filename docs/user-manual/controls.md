---
last_reviewed: 2026-05-18
---

# Controls Reference

This page covers the current keyboard controls for Hypnograph Studio. Most commands
are also available from the macOS menu bar.

Single-key controls apply only when the main Hypnograph window is active and text
input is not focused. Direct keyboard controls, such as Space, `S`, Tab, backtick,
and hold behaviors for `1-9`, require the **Override Global Keyboard Controls**
setting.

## App And File

| Command | Shortcut | Notes |
| --- | --- | --- |
| New | `Cmd+N` | Starts fresh |
| New Composition | `Cmd+Shift+N` | Adds a new composition |
| Open | `Cmd+O` | Opens an existing Hypnograph file |
| Save | `Cmd+S` | Saves the current file |
| Save As | `Cmd+Shift+S` | Saves a copy |
| Save Composition | `Cmd+Option+S` | Saves the current composition |
| Save Composition As | `Cmd+Option+Shift+S` | Saves the current composition as a copy |
| Save & Render | `Ctrl+Cmd+S` | Saves and renders the current composition |
| Save & Render Sequence | `Ctrl+Cmd+Shift+S` | Saves and renders the current sequence |
| Open Effects Composer | `Cmd+Option+K` | Available when Effects Composer is enabled |

## Panels And Views

| Command | Shortcut | Notes |
| --- | --- | --- |
| Properties | `Option+1` | Toggles the Properties panel |
| New Compositions | `Option+2` | Toggles the New Compositions panel |
| Effect Chains | `Option+3` | Toggles the Effect Chains panel |
| Hypnograms | `Option+4` | Toggles the Hypnograms panel |
| Hide Panels | `Tab` | Hides or restores Studio panels |
| Show Full Clips | `F` | Toggles full clip display in the timeline |

## Live Display

| Command | Shortcut | Notes |
| --- | --- | --- |
| Live Preview | `W` | Toggles the Live Preview panel |
| Live Mode | `Cmd+L` | Toggles Live Mode |
| External Monitor | `Cmd+Shift+L` | Toggles the external live display |
| Send to Live Display | `Cmd+Return` | Sends the current composition to the live display |
| Reset Live Display | `Cmd+Shift+R` | Resets the live display |

## Playback

| Command | Shortcut | Notes |
| --- | --- | --- |
| Play/Pause | `Space` | Direct keyboard control |
| Next Composition | `Right Arrow` | Moves to the next composition |
| Previous Composition | `Left Arrow` | Moves to the previous composition |
| Loop Composition | `L` | Loops the current composition |
| Loop Sequence | `Shift+L` | Loops the sequence |
| Generate at End | `G` | Toggles generation at the end of playback |
| Save Snapshot Image | `S` | Direct keyboard control |

## Composition

| Command | Shortcut | Notes |
| --- | --- | --- |
| Favorite | `Cmd+F` | Favorites the current composition |
| Delete | `Cmd+Delete` | Deletes the current composition |
| Next Composition Effect | `E` | Advances the composition effect chain |
| Previous Composition Effect | `Shift+E` | Moves backward through the composition effect chain |
| Clear Composition Effect | `C` | Clears the composition effect |
| Suspend Composition Effects | Hold `` ` `` | Direct keyboard control while the key is held |

## Layers And Sources

| Command | Shortcut | Notes |
| --- | --- | --- |
| Add Random Source | `Shift+N` | Adds a random source |
| Cycle Blend Mode | `M` | Cycles the selected layer blend mode |
| Delete Layer | `Delete` | Removes the selected layer |
| Clear Layer Effect | `Shift+C` | Clears the selected layer effect |
| Next Layer Effect | `Cmd+E` | Advances the selected layer effect chain |
| Previous Layer Effect | `Cmd+Shift+E` | Moves backward through the selected layer effect chain |
| New Random Source | `.` | Replaces the selected source with a random source |
| Favorite Source | `Shift+F` | Favorites the selected source |
| Exclude Source | `Shift+X` | Excludes the selected source |
| Next Source Or Layer | `Option+Right Arrow` | Selects the next source/layer |
| Previous Source Or Layer | `Option+Left Arrow` | Selects the previous source/layer |
| Select Layer 1-9 | `1-9` | Selects the corresponding layer |

## Direct Hold Controls

These controls are handled directly by Hypnograph rather than by the standard macOS
menu shortcut system.

| Key | Behavior | Notes |
| --- | --- | --- |
| `1-9` | Select and hold-to-solo a layer | Suspends composition effects while the layer is soloed |
| `1-9` double-tap | Latch solo mode | Any later `1-9` press clears the latch |
| `` ` `` | Hold to suspend composition effects | Restores composition effects when released |
| `Tab` or `Shift+Tab` | Hide or restore panels | Direct keyboard override for panel visibility |

*Source of truth: `Hypnograph/App/AppCommands.swift`,
`Hypnograph/App/Studio/Menus.swift`, and
`Hypnograph/App/HypnographAppDelegate.swift`.*
