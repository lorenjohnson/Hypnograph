---
doc-status: done
---

# Save Fullscreen State

**Created:** 2026-01-24
**Updated:** 2026-02-27

## Overview

SwiftUI windows remember size/position between launches but not fullscreen state. Add fullscreen persistence so the app restores to fullscreen if that's how the user left it.

## Plan

Persist fullscreen preference alongside window state and restore it on launch.

- [x] Persist `mainWindowFullScreen` (default: `true` for first launch) in window-state storage
- [x] Save state when window enters/exits fullscreen
- [x] Restore on launch via `window.toggleFullScreen(nil)` when preference is true
- [x] Save window state consistently on app terminate (not only when unsaved effect changes exist)

## Implementation Notes

- Added fullscreen enter/exit observers on the resolved main app window in `HypnographAppDelegate`.
- Added persisted `mainWindowFullScreen` support in `HypnographState` window-state load/save flow with legacy decode fallback.
- Wired callbacks in `HypnographApp` so fullscreen changes are captured and persisted immediately.

(Could also just use UserDefaults directly — simpler if we're not already invested in WindowState.)

## Notes

**Why doesn't SwiftUI do this automatically?** SwiftUI's window restoration handles frame (size/position) but not fullscreen. It's a gap in SwiftUI — AppKit apps with proper `NSWindowRestoration` do restore fullscreen automatically.

**Is this okay to do?** Yes. Apple's own apps (Safari, Photos, Preview) restore fullscreen state. It's expected behavior for media apps. No HIG issues.
