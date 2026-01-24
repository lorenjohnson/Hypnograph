# Save Fullscreen State

**Status:** Planning
**Created:** 2026-01-24

## Overview

SwiftUI windows remember size/position between launches but not fullscreen state. Add fullscreen persistence so the app restores to fullscreen if that's how the user left it.

## Plan

Extend existing `WindowState.swift` with a `mainWindowFullScreen` bool. The persistence and save-on-terminate logic is already wired up in `HypnographAppDelegate`.

- [ ] Add `mainWindowFullScreen: Bool` to `WindowState` (default: `true` for first launch)
- [ ] Save state when window enters/exits fullscreen
- [ ] Restore on launch via `window.toggleFullScreen(nil)` if flag is true

(Could also just use UserDefaults directly — simpler if we're not already invested in WindowState.)

## Notes

**Why doesn't SwiftUI do this automatically?** SwiftUI's window restoration handles frame (size/position) but not fullscreen. It's a gap in SwiftUI — AppKit apps with proper `NSWindowRestoration` do restore fullscreen automatically.

**Is this okay to do?** Yes. Apple's own apps (Safari, Photos, Preview) restore fullscreen state. It's expected behavior for media apps. No HIG issues.
