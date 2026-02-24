# In-App Windowing Review

**Status:** Planning
**Created:** 2026-01-24

## Overview

Explore the in-app windowing system (Player Settings, Effects, HUD, etc.) to be more idiomatic / Swift native while still being unobtrusive with sensible UX. The hidden work is deciding and designing the UI/UX first: which windows exist, what goes in them, and what do they look like?

Also: ensure window state (open/closed) is saved and restored between sessions.

## Current Windows/Panels

- **HUD View** (`I`) — Info overlay with layers list, tooltips
- **Effects Editor** (`E`) — Effect chain selection and parameter editing
- **Hypnogram List** (`H`) — History/favorites/recent hypnograms
- **Player Settings** (`P`) — Playback configuration, audio, transitions
- **Watch View** (`W`) — Watching mode display (?)

## Questions to Answer

### Window Design
- [ ] Which windows exist and what goes in them?
- [ ] Should some windows be consolidated? (see [combine-hud-into-player-settings](combine-hud-into-player-settings.md))
- [ ] What's the visual language — floating panels? Sidebars? Modal sheets?
- [ ] How do windows behave with fullscreen?

### Window State Persistence
- [ ] Is window state (open/closed) already being saved? (Note: "I thought I already did this?")
- [ ] If not, add persistence via WindowState.swift
- [ ] Should window positions also be saved?

### Tab Key Behavior
- [ ] When Tab is pressed with no windows shown, show a default set (Player Settings + Effects)
- [ ] Is this the right default set?
- [ ] Should Tab cycle through window visibility states?

## Prototype Findings (2026-01-25)

Built a quick prototype comparing native SwiftUI sidebars vs current floating panels.

### Decision: Use Native Sidebars + Controls

**Strongly prefer native approach:**
- Left sidebar + right sidebar (overlay video, don't resize it)
- Native SwiftUI controls (Slider, Toggle, Picker, Stepper) instead of custom ones
- Tab bar for Live/Preview mode switching
- Show/hide via on-screen icons AND single-key shortcuts (`[` for left, `]` for right)

**Benefits:**
- Less custom code to maintain
- Consistent macOS look and feel
- Built-in accessibility
- Reduces codebase complexity

### SwiftUI Terminology

| Term | Usage |
|------|-------|
| Sidebar | Left/right panels that overlay content |
| `.ultraThinMaterial` | Frosted glass background effect |
| `TabView` | For switching between modes/sections |
| Native controls | `Slider`, `Toggle`, `Picker`, `Stepper` |

### Proposed Layout

```text
┌─────────────────┬────────────────────────────────────┬─────────────────┐
│  LEFT SIDEBAR   │                                    │  RIGHT SIDEBAR  │
│  [Sources]      │         VIDEO CONTENT              │  [Layers]       │
│  [Settings]     │         (full size)                │  [Effects]      │
│  [Favorites]    │                                    │                 │
└─────────────────┴────────────────────────────────────┴─────────────────┘
```

### Next Steps

- [ ] Spec out exactly what goes in each sidebar tab
- [ ] Design the Layers panel in detail (per-layer effect editing)
- [ ] Decide on Tab bar placement for Live/Preview mode
- [ ] Plan migration from custom controls to native ones

## Related Projects

- [combine-hud-into-player-settings](combine-hud-into-player-settings.md) — May eliminate HUD as a separate window

## Notes

Files involved:
- [WindowState.swift](../../../Hypnograph/WindowState.swift) — Window visibility state
- [WindowRegistration.swift](../../../Hypnograph/WindowRegistration.swift) — Window management
- [ContentView.swift](../../../Hypnograph/Views/ContentView.swift) — Main view with overlays
