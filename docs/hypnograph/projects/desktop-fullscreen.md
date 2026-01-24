# Feature: Window Fullscreen Mode

## Current Behavior

**Both apps** now use standard SwiftUI windowing with native macOS fullscreen support (green button / ⌃⌘F).

## Outstanding Issue: Fullscreen State Persistence

SwiftUI windows automatically remember their size/position between launches, but **do not** automatically remember fullscreen state.

### Implementation Options

| Approach | Complexity | Notes |
|----------|------------|-------|
| **A. NSWindowDelegate** | Medium | Watch `windowDidEnterFullScreen` / `windowDidExitFullScreen`, persist to UserDefaults, restore in `applicationDidFinishLaunching` |
| **B. Polling NSWindow state** | Low | Check `window.styleMask.contains(.fullScreen)` periodically or on app termination, save to UserDefaults |
| **C. Extend existing WindowState** | Low | Add `isFullScreen: Bool` to existing `WindowState.swift` persistence |

### Recommended: Option C

We already have `WindowState.swift` with disk persistence and save-on-terminate logic wired up in `HypnographAppDelegate`. Adding a `mainWindowFullScreen` bool there is minimal work.

**To restore on launch:**
```swift
// In onAppear or applicationDidFinishLaunching:
if state.windowState.mainWindowFullScreen {
    window.toggleFullScreen(nil)
}
```

**Default to fullscreen on first launch:** Set `mainWindowFullScreen = true` as the default value in `WindowState`.
