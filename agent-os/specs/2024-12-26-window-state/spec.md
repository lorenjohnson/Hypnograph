# Window State Architecture

## Implementation (as of 2025-12-27)

### Overview

The window visibility system manages which overlays/panels are shown and supports a "clean screen" mode (Tab key) that temporarily hides all windows.

**Single Source of Truth**: All window visibility is stored in `HypnographState.windowState`. Views and menus access it directly via the `Window` enum.

### Components

#### 1. Window (enum)
```swift
enum Window: CaseIterable {
    case hud
    case effectsEditor
    case playerSettings
    case hypnogramList
    case performancePreview
}
```

#### 2. WindowState (struct)
Location: `Hypnograph/WindowState.swift`

```swift
struct WindowState {
    var hud: Bool = false
    var effectsEditor: Bool = false
    var playerSettings: Bool = false
    var hypnogramList: Bool = false
    var performancePreview: Bool = false
    var isCleanScreen: Bool = false

    func isVisible(_ window: Window) -> Bool  // Respects clean screen
    mutating func toggle(_ window: Window)    // Exits clean screen first if active
    mutating func set(_ window: Window, visible: Bool)
    mutating func toggleCleanScreen()
}
```

#### 3. HypnographState
- Owns `@Published var windowState = WindowState()`
- That's it. No convenience wrappers needed.

#### 4. Views & Menus
Access window state directly:
```swift
// Check visibility
if state.windowState.isVisible(.hud) { ... }

// Toggle
state.windowState.toggle(.effectsEditor)

// Set directly
state.windowState.set(.playerSettings, visible: false)
```

#### 5. DreamPlayerState
- **No window-related code at all**
- Manages only playback state, recipe, effects

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        HypnographState                          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              windowState: WindowState                    │   │
│  │                                                          │   │
│  │  Windows (via enum):                                     │   │
│  │  • .hud              • .hypnogramList                    │   │
│  │  • .effectsEditor    • .performancePreview               │   │
│  │  • .playerSettings                                       │   │
│  │                                                          │   │
│  │  isCleanScreen: Bool  ← When true, all isVisible = false │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
         ▲
         │ Direct access via state.windowState
         │
┌─────────────────────────────────────────────────────────────────┐
│                     Views & Menus                               │
│                                                                 │
│  state.windowState.isVisible(.hud)                              │
│  state.windowState.toggle(.effectsEditor)                       │
│  state.windowState.set(.playerSettings, visible: false)         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Behaviors

### Clean Screen (Tab)
- `toggleCleanScreen()` sets `isCleanScreen = true` (only if any window visible)
- When `isCleanScreen` is true, all `isVisible()` calls return `false`
- Toggling any window while in clean screen exits clean screen first (consumes keypress)
- Toggling Tab again exits clean screen, restoring previous visibility

### Window Toggle Flow
1. User presses `I` (HUD shortcut)
2. Menu calls `state.windowState.toggle(.hud)`
3. `WindowState.toggle(.hud)`:
   - If `isCleanScreen`, sets it to `false` and returns (consumed)
   - Otherwise, toggles `hud` boolean
4. SwiftUI observes `@Published windowState` change and updates UI

---

## Design Principles

1. **Single source of truth** - All visibility in `HypnographState.windowState`
2. **Use the enum** - No per-window properties or methods scattered across classes
3. **No indirection** - Views access `state.windowState` directly
4. **Clean screen is automatic** - `isVisible()` handles the check
5. **Adding a window** - Just add to `Window` enum and `WindowState` struct

