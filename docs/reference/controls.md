---
last_reviewed: 2026-01-27
---

# Controls Reference

This is the canonical reference for keyboard shortcuts and controller mappings.
Source of truth: `Hypnograph/HypnographApp.swift`, `Hypnograph/Dream/Dream.swift`,
`Divine/Divine.swift`, `Hypnograph/GameControllerManager.swift`.

## Keyboard Shortcuts

### App Commands (global, `Hypnograph/HypnographApp.swift`)

| Area | Command | Key | Notes |
| --- | --- | --- | --- |
| App | Play/Pause | `Space` | Toggles Dream playback only |
| File | New | `Cmd+N` | Per current module |
| File | Save Hypnogram | `Cmd+S` | Divine save is a no-op |
| File | Save Hypnogram As | `Cmd+Shift+S` | Dream only |
| File | Open Hypnogram | `Cmd+O` | Dream only |
| View | Dream | `Cmd+Shift+1` | Switch module |
| View | Divine | `Cmd+Shift+2` | Switch module |
| View | Cycle Module | `~` | Disabled while typing |
| View | Watch | `W` | Disabled while typing |
| Overlays | Left Sidebar | `[` | Disabled while typing |
| Overlays | Right Sidebar | `]` | Disabled while typing |
| Overlays | Hypnogram List | `H` | Dream only |
| Overlays | Toggle Panels | `Tab` | Toggles Studio panels on or off; auto-hide only controls whether visible panels hide again after inactivity |
| Live | Live Preview | `L` | Dream only |
| Live | Live Mode | `Cmd+L` | Dream only |
| Live | External Monitor | `Cmd+Shift+L` | Dream only |
| Live | Send to Live Display | `Cmd+Return` | Dream only |
| Live | Reset Live Display | `Cmd+Shift+R` | Dream only |
| Sources | Custom Photos Selection | `Cmd+Shift+O` | Opens picker |

### Dream Mode (Composition menu, `Hypnograph/Modules/Dream/Dream.swift`)

| Command | Key | Notes |
| --- | --- | --- |
| Cycle Mode (Montage/Sequence/Live) | `` ` `` | Disabled while typing |
| Cycle Effect Forward | `Cmd+E` | Current layer |
| Cycle Effect Backward | `Cmd+Shift+E` | Current layer |
| Add Source | `Shift+N` | Disabled while typing |
| Next Source | `Right` | Disabled while typing |
| Previous Source | `Left` | Disabled while typing |
| Select Source 1-9 | `1-9` | Disabled while typing; **hold** to solo source (see Key Hold Behaviors) |
| Select Global Layer | `0` | Disabled while typing; **hold** to suspend global effects (see Key Hold Behaviors) |
| Clear Current Layer Effect | `C` | Disabled while typing |
| Clear All Effects | `Ctrl+Shift+C` | Not disabled |
| New Hypnogram | `N` | Disabled while typing |
| Save Hypnogram | `Cmd+S` | Duplicates app menu |
| Favorite Hypnogram | `Cmd+F` | |

### Dream Mode (Source menu, `Hypnograph/Modules/Dream/Dream.swift`)

| Command | Key | Notes |
| --- | --- | --- |
| Cycle Blend Mode | `M` | Disabled while typing |
| New Random Clip | `.` | Disabled while typing |
| Delete Source | `Delete` | Disabled while typing |
| Add to Exclude List | `Shift+X` | |
| Toggle Favorite | `Shift+F` | |

### Divine Mode (Composition menu, `Hypnograph/Modules/Divine/Divine.swift`)

| Command | Key | Notes |
| --- | --- | --- |
| Add Card | `.` | |
| Next Card | `Right` | |
| Previous Card | `Left` | |
| Select Card 1-9 | `1-9` | |
| Clear Table | `Cmd+N` | |
| Zoom In | `Cmd+=` | |
| Zoom Out | `Cmd+-` | |
| Reset Zoom | `Cmd+0` | |

### Divine Mode (Source menu, `Hypnograph/Modules/Divine/Divine.swift`)

| Command | Key | Notes |
| --- | --- | --- |
| New Random Card | `Shift+N` | |
| Delete Card | `Delete` | |
| Add to Exclude List | `Shift+X` | |
| Toggle Favorite | `Shift+F` | |

### Panels and Modals

| Panel | Key | Notes |
| --- | --- | --- |
| ModalPanel sheets | `Esc` | Close panel |

## Key Hold Behaviors (Montage Mode Only)

These behaviors use NSEvent monitors in `HypnographApp.swift` to detect keyDown/keyUp
events for true hold detection (not key repeat).

| Key | Hold Behavior | Notes |
| --- | --- | --- |
| `0` | Suspend global effects | Shows all layers with their source effects but bypasses the global effect chain |
| `1-9` | Solo source + suspend global effects | Shows only that source with its effect applied, bypasses global effects for effect preview |
| `1-9` (double-tap) | Latch solo mode | Solo stays active until any number key is pressed again |

**Use case**: When applying effects to individual sources, hold the source number key to
preview just that layer with its effect, without the global effect chain interfering.
Double-tap to lock the solo so you can work hands-free. Any subsequent 1-9 key press clears the latch.

## HUD Notes

HUD items are currently disabled (`Dream.hudItems()` returns an empty list) and the
legacy `HUDView` overlay is deprecated in favor of the new right sidebar (Composition tab).

## Game Controller Mapping

Source: `Hypnograph/GameControllerManager.swift`.

### Summary

- **A**: New (Dream/Divine)
- **B**: Save (Dream/Divine)
- **X**: Cycle effect (Dream only, current layer)
- **Y**: Save Hypnogram (Dream only)
- **D-Pad Left/Right**: Previous/Next source or card
- **D-Pad Up/Down**: Add/Delete source or card
- **LB**: Cycle blend mode (Dream only)
- **RB**: Cycle effect backward (Dream only, current layer)
- **LT**: Clear all effects and reset blend modes (Dream only)
- **RT**: Toggle mode (Montage/Sequence) (Dream only)
- **Start/Menu**: Pause/Play (Dream only)
- **L3**: Toggle Watch mode
- **R3**: Send to Live Display (Dream only; requires performance display visible)

### Quick Reference Card (Xbox Layout)

```
                    +---------------------------+
                    |       XBOX CONTROLLER     |
                    +---------------------------+

    +-----------------------------------------------------------+
    |                                                           |
    |   LB: Blend Mode          RB: Cycle Effect Backward        |
    |   LT: Clear Effects       RT: Toggle Montage/Sequence      |
    |                                                           |
    |         D-Pad                        Face Buttons          |
    |           ^                              (Y)               |
    |        Add                              Save Hypnogram     |
    |                                                           |
    |      <       >                    (X)       (B)            |
    |    Prev    Next               Cycle Effect   Save           |
    |                                                           |
    |           v                              (A)               |
    |        Delete                             New              |
    |                                                           |
    |   [Back/Options]              [Start/Menu]                 |
    |    Toggle HUD                  Pause/Play                  |
    |                                                           |
    |   L3: Toggle Watch             R3: Send to Live      |
    |                                                           |
    +-----------------------------------------------------------+
```
