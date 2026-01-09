# Feature: Window Fullscreen Mode

## Decision: Use Native macOS Fullscreen

After exploration, we decided to embrace native macOS fullscreen (green button / ⌃⌘F) rather than the custom "borderless" fullscreen that stays on the desktop. Native fullscreen is more familiar to users and integrates properly with Mission Control.

## Current Behavior

**Both apps** now use standard SwiftUI windowing with native macOS fullscreen support (green button / ⌃⌘F).

## Outstanding Issue: Fullscreen State Persistence

SwiftUI windows automatically remember their size/position between launches, but **do not** automatically remember fullscreen state.

### Why No Native Solution?

macOS window restoration handles frames but not the fullscreen toggle. Manual tracking is required.

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

## Legacy Code: Borderless Fullscreen

The `makeBorderlessHypnoWindow` extension is kept in `HypnoCore/Extensions/AppKit.swift` in case we want to return to this approach. It creates a fullscreen window that stays on the current desktop/Space rather than creating a new Space like native fullscreen.
