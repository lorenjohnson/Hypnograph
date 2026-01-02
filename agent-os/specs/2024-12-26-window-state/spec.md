# Window State Architecture - Generic Key-Based System

## Overview

The window visibility system manages which overlays/panels are shown and supports a "clean screen" mode (Tab key) that temporarily hides all windows.

**Goal**: Migrate from enum-based window tracking to a generic, key-based system that stores window state in serialized JSON. This allows windows to be added/removed without code changes to the WindowState struct itself.

**Single Source of Truth**: All window visibility is stored in `HypnographState.windowState` using string keys instead of discrete enum cases.

### Components

#### 1. WindowState (struct) - NEW DESIGN
Location: `Hypnograph/WindowState.swift`

**This struct knows NOTHING about specific windows - it's purely generic.**

```swift
struct WindowState: Codable {
    // Generic dictionary-based storage
    // Keys are whatever string IDs windows choose to use
    private var windowVisibility: [String: Bool] = [:]

    var isCleanScreen: Bool = false

    // MARK: - Window Registration

    /// Register a window so it's known to the system
    /// Windows should call this on first appearance (e.g., in view's onAppear)
    mutating func register(_ windowID: String, defaultVisible: Bool = false) {
        // Only register if not already known
        if windowVisibility[windowID] == nil {
            windowVisibility[windowID] = defaultVisible
        }
    }

    // MARK: - Window Access

    /// Check if a window is visible (respects clean screen)
    func isVisible(_ windowID: String) -> Bool {
        if isCleanScreen { return false }
        return windowVisibility[windowID] ?? false
    }

    /// Toggle a window's visibility
    /// - Returns: true if the toggle was consumed by exiting clean screen
    @discardableResult
    mutating func toggle(_ windowID: String) -> Bool {
        if isCleanScreen {
            isCleanScreen = false
            return true  // Consumed
        }
        windowVisibility[windowID] = !(windowVisibility[windowID] ?? false)
        return false
    }

    /// Set a window's visibility directly
    mutating func set(_ windowID: String, visible: Bool) {
        if visible && isCleanScreen {
            isCleanScreen = false
        }
        windowVisibility[windowID] = visible
    }

    /// Toggle clean screen mode
    /// If exiting clean screen and no windows are visible, shows all registered windows
    mutating func toggleCleanScreen() {
        if isCleanScreen {
            // Exiting clean screen
            isCleanScreen = false

            // If no windows are currently visible, show all registered windows as a "reset"
            if !hasAnyWindowVisible {
                for windowID in windowVisibility.keys {
                    windowVisibility[windowID] = true
                }
            }
        } else {
            // Entering clean screen (only if something is visible)
            if hasAnyWindowVisible {
                isCleanScreen = true
            }
        }
    }

    /// Whether any window is currently visible
    var hasAnyWindowVisible: Bool {
        windowVisibility.values.contains(true)
    }
}
```

**That's it. No window-specific constants, no enum cases, no knowledge of what windows exist.**

#### 2. Window Registration System

**Design Goal**: Windows should self-register automatically without boilerplate.

**Approach**: Create a protocol or view modifier that handles registration automatically when a window appears. This eliminates the need for manual `.onAppear` registration in every view.

**Possible implementations** (implementer decides):
- Protocol with default implementation
- View modifier/wrapper
- Custom property wrapper
- SwiftUI ViewModifier

**Requirements**:
- Windows provide a `windowID: String`
- Registration happens automatically on first appearance
- No manual `.onAppear` calls needed in window views
- Clean, declarative syntax

#### 3. HypnographState

- Owns `@Published var windowState = WindowState()`
- That's it. No convenience wrappers needed.

#### 4. Usage Patterns

**In Views:**
- Windows identify themselves with a string ID
- Views check visibility via `state.windowState.isVisible(windowID)`
- Registration handled automatically by the registration system (see #2)

**In Menus:**
- Toggle windows: `state.windowState.toggle("effectsEditor")`
- Set visibility: `state.windowState.set("playerSettings", visible: false)`

**Dynamic Windows:**
- Can use computed IDs: `"layer-\(index)"`

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
│  │  windowVisibility: [String: Bool]                        │   │
│  │    "hud" → true                                          │   │
│  │    "effectsEditor" → false                               │   │
│  │    "playerSettings" → true                               │   │
│  │    "hypnogramList" → false                               │   │
│  │    "performancePreview" → false                          │   │
│  │    "layer-3" → true                                      │   │
│  │    [any window can register itself...]                   │   │
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
│  state.windowState.isVisible("hud")                             │
│  state.windowState.toggle("effectsEditor")                      │
│  state.windowState.set("playerSettings", visible: false)        │
│                                                                 │
│  // Windows self-identify with any string ID they choose        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Behaviors

### Clean Screen (Tab)

**Entering clean screen:**

- `toggleCleanScreen()` sets `isCleanScreen = true` (only if any window visible)
- When `isCleanScreen` is true, all `isVisible()` calls return `false`

**Exiting clean screen:**

- Toggling Tab again exits clean screen
- If any windows were visible before entering clean screen, restores that previous visibility
- If NO windows were visible (empty state), shows ALL registered windows as a "reset" behavior

**Alternative exit:**

- Toggling any individual window while in clean screen exits clean screen first (consumes keypress)

### Window Toggle Flow
1. User presses `I` (HUD shortcut)
2. Menu calls `state.windowState.toggle("hud")`
3. `WindowState.toggle("hud")`:
   - If `isCleanScreen`, sets it to `false` and returns (consumed)
   - Otherwise, toggles the boolean value in `windowVisibility["hud"]`
4. SwiftUI observes `@Published windowState` change and updates UI

---

## Design Principles

1. **Single source of truth** - All visibility in `HypnographState.windowState`
2. **Completely generic** - `WindowState` has ZERO knowledge of specific windows
3. **Self-identifying windows** - Each window/view chooses its own string ID
4. **Self-registration** - Windows register themselves on first appearance via `register()`
5. **No central registry** - No need to maintain a list of all window IDs
6. **No indirection** - Views access `state.windowState` directly
7. **Clean screen is automatic** - `isVisible()` handles the check
8. **Codable for persistence** - `WindowState` conforms to `Codable` for automatic JSON serialization

## Benefits of This Approach

- **Zero code changes to `WindowState`** when adding/removing windows
- **Automatic persistence** - `Codable` means the entire state (including all window visibility) serializes to JSON for saving on app exit
- **Dynamic window support** - Can create windows with computed IDs (e.g., `"layer-\(index)"`)
- **No maintenance burden** - No enums, no switch statements, no central registry
- **Windows are decoupled** - Each view manages its own ID, no shared knowledge required

## Migration Notes

The refactor changes:
- **Delete** `Window` enum entirely
- Replace individual Bool properties → `windowVisibility: [String: Bool]` dictionary
- Replace switch statements → Direct dictionary access
- `.hud` → `"hud"` (or define locally in the view: `private let windowID = "hud"`)

## Persistence Strategy

**Requirement**: Window state (including all window visibility and `isCleanScreen`) must persist across app launches.

**Approach**: Since `WindowState` conforms to `Codable`, use JSON serialization to save/restore state.

**Implementation details** (implementer decides):
- Storage mechanism (UserDefaults, file system, etc.)
- When to save (app exit, periodic, on change, etc.)
- Error handling strategy

