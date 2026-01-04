---
last_reviewed: 2026-01-03T21:17:01Z
---

# Dream Players Architecture

## Scope
This document covers the Dream module, its player state model, and the
performance display pipeline.

## Sources
- `Hypnograph/Modules/Dream/Dream.swift`
- `Hypnograph/Modules/Dream/DreamPlayerState.swift`
- `Hypnograph/PlayerConfiguration.swift`
- `Hypnograph/Modules/PerformanceDisplay/LivePlayer.swift`
- `Hypnograph/HypnographState.swift`

## Module Overview

### Dream
- The Dream module is a coordinator that owns:
  - `montagePlayer` (layered montage playback)
  - `sequencePlayer` (clip sequence playback)
  - `livePlayer` (performance display output)
- `mode` selects the active player: montage or sequence.
- `performanceMode` toggles between edit (local preview) and live (mirror
  performance display).

### Active Player Selection
- `activePlayer` is `montagePlayer` or `sequencePlayer` based on `mode`.
- `activeEffectManager` and `effectsSession` switch to the live player when
  `performanceMode` is `.live`.

## DreamPlayerState
- Owns the recipe, per-player config, and playback state.
- Holds its own `EffectsSession` and `EffectManager`.
- Provides navigation helpers and source/layer selection.
- Synchronizes `playRate` between `recipe` and `config`.

## PlayerConfiguration
- Per-player configuration for aspect ratio, resolution, target duration, and
  source generation limits.
- Stored in settings as `montagePlayerConfig` and `sequencePlayerConfig`.
- `viewID` encodes configuration for SwiftUI identity changes.

## Recipe Generation
- Dream uses `HypnographState.library.randomClip()` to generate new sources.
- Montage mode assigns a base layer plus randomized blend modes.
- Sequence mode uses variable clip lengths for per-source timing.

## Performance Display (LivePlayer)
- Owns its own `EffectManager` and `EffectsSession` (`live-effects.json`).
- Uses two internal `AVPlayer` instances (A/B) with crossfade transitions.
- Can render to a fullscreen external monitor or a windowed preview.
- Syncs performance display with active source in sequence mode.

## Audio Routing
- Preview and performance output have independent audio devices and volumes.
- Dream persists device UIDs and volumes in `Settings`.
- Audio device changes fall back to system default when devices disconnect.

## Integration Points
- `Dream.makeDisplayView()` selects montage or sequence views using
  `RenderEngine.makePlayerItem()` results.
- Dream export uses `RenderEngine.ExportQueue` with per-player sizing/timeline.
- `HypnographState.onWatchTimerFired` is wired to `Dream.new()` for auto-generation.
- `EffectsEditorView` edits the `EffectsSession` used by the active player or
  live mode.
