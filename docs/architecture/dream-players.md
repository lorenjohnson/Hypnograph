---
last_reviewed: 2026-01-03T21:17:01Z
---

# Dream Players Architecture

## Scope
This document covers the Dream module, its player state model, and the
performance display pipeline.

## Sources
- `Hypnograph/Dream/Dream.swift`
- `Hypnograph/Dream/DreamPlayerState.swift`
- `Hypnograph/PlayerConfiguration.swift`
- `Hypnograph/Dream/LivePlayer.swift`
- `Hypnograph/HypnographState.swift`

## Module Overview

### Dream
- The Dream module is a coordinator that owns:
  - `player` (preview deck playback)
  - `livePlayer` (performance display output)
- `isLiveMode` selects the target surface for actions (preview vs live output).

### Active Player Selection
- `activePlayer` is always the preview `player`.
- Live output has its own `EffectManager` and `EffectsSession` owned by `livePlayer`.

## DreamPlayerState
- Owns the recipe, per-player config, and playback state.
- Holds its own `EffectsSession` and `EffectManager`.
- Provides navigation helpers and source/layer selection.
- Exposes `playRate` and `targetDuration` as convenience accessors on the recipe.

## PlayerConfiguration
- Per-player configuration for aspect ratio, resolution, and generation limits.
- Stored in settings as `playerConfig` (legacy keys are decoded and migrated).
- `viewID` encodes configuration for SwiftUI identity changes.

## Recipe Generation
- Dream uses `HypnographState.library.randomClip()` to generate new sources.
- Generation produces a layered montage clip (1…N layers) with a randomized target duration.

## Live Display (LivePlayer)
- Owns its own `EffectManager` and shares the global `EffectsSession` (`effects-library.json`).
- Uses two internal `AVPlayer` instances (A/B) with crossfade transitions.
- Can render to a fullscreen external monitor or a windowed preview.

## Audio Routing
- Preview and performance output have independent audio devices and volumes.
- Dream persists device UIDs and volumes in `Settings`.
- Audio device changes fall back to system default when devices disconnect.

## View Naming Conventions

The codebase uses consistent suffixes to distinguish view types:

| Suffix   | Meaning                                            | Examples                                  |
| -------- | -------------------------------------------------- | ----------------------------------------- |
| `Screen` | Full-screen SwiftUI view (takes over main content) | `LivePlayerScreen`                        |
| `Panel`  | Partial UI element (sidebar, popover)              | `LivePreviewPanel`                        |
| `View`   | General-purpose reusable view component            | `MontagePlayerView`, `SequencePlayerView` |

Note: `MontagePlayerView` is an `NSViewRepresentable` bridge
to AppKit's `AVPlayerView`, but from the file/naming perspective they're treated as
regular views since the implementation detail isn't meaningful at that level.

## Integration Points

- `MontagePlayerView` and `LivePlayer` build `AVPlayerItem`s via `RenderEngine.makePlayerItem()`.
- Dream export uses `RenderEngine.ExportQueue` with per-player sizing/timeline.
- `HypnographState.onWatchTimerFired` is wired to `Dream.new()` for auto-generation.
- `EffectsEditorView` edits the `EffectsSession` used by the active player or
  live mode.
