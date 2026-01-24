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

## Related Projects

- [combine-hud-into-player-settings](combine-hud-into-player-settings.md) — May eliminate HUD as a separate window

## Notes

Files involved:
- [WindowState.swift](../../../Hypnograph/WindowState.swift) — Window visibility state
- [WindowRegistration.swift](../../../Hypnograph/WindowRegistration.swift) — Window management
- [ContentView.swift](../../../Hypnograph/Views/ContentView.swift) — Main view with overlays
