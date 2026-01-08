# Feature: Desktop Full Screen Mode (Borderless Hypno Window)

## Goal
Add a toggleable "Desktop Full Screen" mode to Divine (and later Hypnograph) that makes the window borderless and fills the screen while staying on the desktop (not Apple's native fullscreen which creates a separate Space).

## Current State

### Completed
- `HypnoWindowState` struct in `HypnoCore/Extensions/AppKit.swift` - Codable for persistence
- `NSWindow.captureHypnoState()` - Captures current window state
- `NSWindow.makeBorderlessHypnoWindow(on:)` - Applies borderless fullscreen, returns saved state
- `NSWindow.restoreFromHypnoState(_:animate:)` - Restores window from saved state

### Not Yet Implemented

#### Divine Integration
- Add `weak var mainWindow: NSWindow?` to `DivineAppDelegate`
- Add `isDesktopFullScreen: Bool` state (persisted to UserDefaults/SettingsStore)
- Add `savedWindowState: HypnoWindowState?` (persisted)
- Wire up window reference in `DivineApp.body` `.onAppear`
- Add Window menu item: "Desktop Full Screen" with toggle (⌘⇧F suggested)
- On launch: if `isDesktopFullScreen` was true, restore that mode

#### Hypnograph Integration (optional/future)
- Currently always launches in borderless mode
- Would need to make this optional via similar menu toggle
- More complex since it has multiple windows/screens

## Key Files
- `HypnoCore/Extensions/AppKit.swift` - The extension (currently unstaged)
- `Divine/DivineApp.swift` - App entry point, needs window wiring
- `Divine/DivineAppCommands.swift` - Menu commands, needs Window menu section

## API Usage Pattern

```swift
// In app delegate
var savedWindowState: HypnoWindowState?
var isDesktopFullScreen = false

func toggleDesktopFullScreen() {
    guard let window = mainWindow else { return }

    if let saved = savedWindowState {
        // Exit desktop fullscreen
        window.restoreFromHypnoState(saved)
        savedWindowState = nil
        isDesktopFullScreen = false
    } else {
        // Enter desktop fullscreen
        savedWindowState = window.makeBorderlessHypnoWindow(on: window.screen ?? NSScreen.main!)
        isDesktopFullScreen = true
    }
    // Persist state...
}
```

## Git Status
- Extensions consolidation committed (67833ae)
- `HypnoWindowState` + NSWindow extensions **unstaged** in working directory

---

## WIP Code: Add to AppKit.swift

Add this after the `NSColor` extension in `HypnoCore/Extensions/AppKit.swift`:

```swift
// MARK: - NSWindow

/// Saved window state for restoring from borderless mode.
/// Codable for persistence across app launches.
public struct HypnoWindowState: Codable {
    public let frameX: CGFloat
    public let frameY: CGFloat
    public let frameWidth: CGFloat
    public let frameHeight: CGFloat
    public let styleMaskRawValue: UInt
    public let collectionBehaviorRawValue: UInt
    public let titleVisibilityRawValue: Int
    public let titlebarAppearsTransparent: Bool
    public let isOpaque: Bool
    public let backgroundColorHex: String
    public let levelRawValue: Int
    public let isMovable: Bool

    public var frame: NSRect {
        NSRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
    }

    public var styleMask: NSWindow.StyleMask {
        NSWindow.StyleMask(rawValue: styleMaskRawValue)
    }

    public var collectionBehavior: NSWindow.CollectionBehavior {
        NSWindow.CollectionBehavior(rawValue: collectionBehaviorRawValue)
    }

    public var titleVisibility: NSWindow.TitleVisibility {
        NSWindow.TitleVisibility(rawValue: titleVisibilityRawValue) ?? .visible
    }

    public var level: NSWindow.Level {
        NSWindow.Level(rawValue: levelRawValue)
    }

    public var backgroundColor: NSColor {
        NSColor.fromHex(backgroundColorHex) ?? .windowBackgroundColor
    }
}

public extension NSWindow {
    /// Capture current window state for later restoration.
    func captureHypnoState() -> HypnoWindowState {
        HypnoWindowState(
            frameX: frame.origin.x,
            frameY: frame.origin.y,
            frameWidth: frame.size.width,
            frameHeight: frame.size.height,
            styleMaskRawValue: styleMask.rawValue,
            collectionBehaviorRawValue: collectionBehavior.rawValue,
            titleVisibilityRawValue: titleVisibility.rawValue,
            titlebarAppearsTransparent: titlebarAppearsTransparent,
            isOpaque: isOpaque,
            backgroundColorHex: backgroundColor.toHex(),
            levelRawValue: level.rawValue,
            isMovable: isMovable
        )
    }

    /// Configure as borderless fullscreen window, capturing state first.
    /// Returns the captured state for later restoration.
    @discardableResult
    func makeBorderlessHypnoWindow(on screen: NSScreen) -> HypnoWindowState {
        let savedState = captureHypnoState()

        let fullFrame = screen.frame

        styleMask.remove(.titled)
        styleMask.remove(.closable)
        styleMask.remove(.miniaturizable)
        styleMask.remove(.resizable)

        collectionBehavior = [.fullScreenNone, .canJoinAllSpaces]

        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        isOpaque = true
        backgroundColor = .black
        level = .normal

        setFrame(fullFrame, display: true, animate: false)
        isMovable = false

        return savedState
    }

    /// Restore window from saved state.
    func restoreFromHypnoState(_ state: HypnoWindowState, animate: Bool = true) {
        styleMask = state.styleMask
        collectionBehavior = state.collectionBehavior
        titleVisibility = state.titleVisibility
        titlebarAppearsTransparent = state.titlebarAppearsTransparent

        standardWindowButton(.closeButton)?.isHidden = false
        standardWindowButton(.miniaturizeButton)?.isHidden = false
        standardWindowButton(.zoomButton)?.isHidden = false

        isOpaque = state.isOpaque
        backgroundColor = state.backgroundColor
        level = state.level
        isMovable = state.isMovable

        setFrame(state.frame, display: true, animate: animate)
    }
}
```
