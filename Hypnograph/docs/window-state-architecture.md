# Window State Architecture

## Implementation (as of 2025-12-27)

### Overview

The window visibility system manages which overlays/panels are shown and supports a "clean screen" mode (Tab key) that temporarily hides all windows.

**Single Source of Truth**: All window visibility is stored in `HypnographState.windowState`. Components like `DreamPlayerState` delegate to the parent via the `WindowStateProvider` protocol.

### Components

#### 1. WindowState (struct)
Location: `Hypnograph/WindowState.swift`

A value type containing:
- Visibility booleans for all windows
- `isCleanScreen` flag
- Toggle/set methods with clean screen awareness

```swift
struct WindowState {
    // Per-player windows
    var hud: Bool = false
    var effectsEditor: Bool = false
    var playerSettings: Bool = false

    // App-level windows
    var hypnogramList: Bool = false
    var performancePreview: Bool = false

    var isCleanScreen: Bool = false

    func isVisible(_ window: Window) -> Bool  // Respects clean screen
    mutating func toggle(_ window: Window)    // Exits clean screen first if active
    mutating func set(_ window: Window, visible: Bool)
    mutating func toggleCleanScreen()
}
```

#### 2. WindowStateProvider (protocol)
```swift
@MainActor
protocol WindowStateProvider: AnyObject {
    var windowState: WindowState { get set }
}
```

#### 3. HypnographState
- Conforms to `WindowStateProvider`
- Owns the single `@Published var windowState = WindowState()`
- Provides computed properties for convenience:
  - `isHypnogramListVisible` → delegates to `windowState.isVisible(.hypnogramList)`
  - `isPerformancePreviewVisible` → delegates to `windowState.isVisible(.performancePreview)`

#### 4. DreamPlayerState
- Has `weak var parentWindowStateProvider: WindowStateProvider?`
- **No local visibility storage** - all computed properties delegate to parent:
  ```swift
  var isHUDVisible: Bool {
      get { parentWindowStateProvider?.windowState.isVisible(.hud) ?? false }
      set { parentWindowStateProvider?.windowState.set(.hud, visible: newValue) }
  }
  ```
- Toggle methods delegate directly: `parentWindowStateProvider?.windowState.toggle(.hud)`

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        HypnographState                          │
│                  (conforms to WindowStateProvider)              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              WindowState (Single Source of Truth)        │   │
│  │                                                          │   │
│  │  All Windows:                                            │   │
│  │  • hud               • hypnogramList                     │   │
│  │  • effectsEditor     • performancePreview                │   │
│  │  • playerSettings                                        │   │
│  │                                                          │   │
│  │  isCleanScreen: Bool  ← When true, all isVisible = false │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
         ▲
         │ weak reference (parentWindowStateProvider)
         │
┌─────────────────────────────────────────────────────────────────┐
│                       DreamPlayerState                          │
│                                                                 │
│  isHUDVisible           ─┐                                      │
│  isEffectsEditorVisible  ├── Computed, delegate to parent       │
│  isPlayerSettingsVisible─┘                                      │
│                                                                 │
│  toggleHUD()            ─┐                                      │
│  toggleEffectsEditor()   ├── Call parent.windowState.toggle()   │
│  togglePlayerSettings() ─┘                                      │
│  toggleCleanScreen()                                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Behaviors

### Clean Screen (Tab)
- Toggling clean screen sets `isCleanScreen = true` (only if any window is visible)
- When `isCleanScreen` is true, all `isVisible()` calls return `false`
- Toggling any window while in clean screen exits clean screen first (consumes keypress)
- Toggling Tab again exits clean screen, restoring previous visibility

### Window Toggle Flow
1. User presses `I` (HUD shortcut)
2. Menu calls `dream.activePlayer.toggleHUD()`
3. `DreamPlayerState.toggleHUD()` calls `parentWindowStateProvider?.windowState.toggle(.hud)`
4. `WindowState.toggle(.hud)`:
   - If `isCleanScreen`, sets it to `false` and returns (consumes keypress)
   - Otherwise, toggles `hud` boolean
5. SwiftUI observes `@Published windowState` change and updates UI

---

## Coupling Summary

```
HypnographApp
    │
    ├── HypnographState (WindowStateProvider)
    │       │
    │       └── windowState: WindowState  ← ALL visibility here
    │
    └── Dream
            │
            ├── montagePlayer: DreamPlayerState
            │       └── parentWindowStateProvider → HypnographState
            │
            └── sequencePlayer: DreamPlayerState
                    └── parentWindowStateProvider → HypnographState
```

**Coupling**: `DreamPlayerState` → `WindowStateProvider` → `HypnographState`

This is clean and minimal - `DreamPlayerState` only needs a weak reference to the provider to access the shared window state.

