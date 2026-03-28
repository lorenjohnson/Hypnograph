---
doc-status: done
---

# Unified Player Architecture

## Status Note

This A/B `AVPlayer`-based architecture was implemented as an intermediate step, but has since been superseded by the Metal Playback Pipeline (Direction A), which replaces `AVPlayerView` + view-level crossfades with a single `MTKView` render surface.

- See: [Metal Playback Pipeline](20260117-metal-playback-pipeline.md)

## Overview

Unify the player infrastructure for Preview and Live into a shared `HypnogramPlayer` class that handles A/B player transitions, playback control, and boundary hooks. This creates a foundation for:

- Smooth visual transitions between hypnograms (crossfade, punk, etc.)
- Consistent watching experience in both Preview and Live
- Boundary hooks for volume leveling and audio smoothing
- Reduced code duplication and easier feature development

## Problem

Today we have two separate player implementations:

| | LivePlayer | MontagePlayerView |
|---|------------|-------------------|
| **Architecture** | A/B players with crossfade | Single player, item swap |
| **Transitions** | Smooth crossfade | Hard cut |
| **Code location** | `Dream/LivePlayer.swift` | `Dream/MontagePlayerView.swift` |
| **View layer** | Owns NSWindow + two AVPlayerViews | SwiftUI NSViewRepresentable |

This divergence means:
- Transition features must be implemented twice
- Preview has jarring hard cuts while Live is smooth
- Future audio boundary hooks would need dual implementations
- Bug fixes may need to be applied in two places

## Proposed Solution

Create a shared `HypnogramPlayer` class that both Preview and Live use:

```
┌─────────────────────────────────────────────────────────┐
│  HypnogramPlayer                                        │
│  - Owns ABPlayerCoordinator (two AVPlayers)             │
│  - Handles composition building                         │
│  - Manages transitions (style, duration, animation)     │
│  - Provides playback control (play/pause/seek)          │
│  - Emits boundary events (willTransition/didTransition) │
└─────────────────────────────────────────────────────────┘
              ▲                           ▲
              │                           │
   ┌──────────┴──────────┐     ┌──────────┴──────────┐
   │  PreviewPlayerView  │     │  LivePlayer         │
   │  (SwiftUI bridge)   │     │  (window manager)   │
   │                     │     │                     │
   │  - Thin wrapper     │     │  - Thin wrapper     │
   │  - SwiftUI bindings │     │  - Window lifecycle │
   │  - Time observer    │     │  - Screen selection │
   └─────────────────────┘     └─────────────────────┘
```

### What HypnogramPlayer handles (shared)

- **A/B player coordination**: Two AVPlayer instances, swap between them
- **Transition execution**: Animate alpha based on style (none/crossfade/punk)
- **Composition building**: Call RenderEngine.makePlayerItem, load into inactive player
- **Playback state**: Play rate, pause, volume, audio device
- **Looping**: End-of-playback notification handling
- **Still-image clips**: Detect all-still compositions, pause on frame 0
- **Boundary hooks**: `willTransition(from:to:)` and `didTransition(to:)` callbacks

### What wrappers handle (specific)

**PreviewPlayerView** (renamed from MontagePlayerView):
- SwiftUI `NSViewRepresentable` bridge
- `currentSourceTime` binding (periodic time observer on active player)
- `isPaused` binding
- `effectsChangeCounter` for redraw-while-paused
- Watch mode timer for still-image auto-advance
- `onClipEnded` callback

**LivePlayer**:
- Window creation and management (fullscreen vs windowed)
- Screen selection (prefer external monitor)
- Show/hide/toggle lifecycle
- Independent EffectManager ownership

## Why A/B Players for Preview?

The original implementation plan considered a "snapshot overlay" approach for Preview:
- Capture last frame as static image
- Swap AVPlayerItem
- Fade snapshot out while new playback fades in

We decided against this because:

1. **Smooth watching is core to Preview too** - Users browse clip history and watch in Preview as much as Live. Hard cuts are jarring.

2. **True audio crossfade potential** - A/B players can overlap audio in the future. Snapshot cannot.

3. **Decode latency protection** - If new AVPlayerItem takes time to decode first frame, A/B hides this. Snapshot might flash.

4. **One implementation to maintain** - Same transition code path for both contexts.

5. **Memory is acceptable** - Two AVPlayers is more memory, but modern Macs handle this fine, and only one composition is "hot" at a time.

## Relationship to Other Projects

### Hypnogram Transitions
This project provides the **foundation** for transitions. The transitions project defines:
- Transition styles (None, Crossfade, Punk)
- User-facing settings
- Duration controls

This project provides the **infrastructure** to implement those styles.

### Volume Leveling
The `willTransition` / `didTransition` boundary hooks created here are the integration point for:
- Audio fades at clip boundaries
- Volume leveling gain ramps between hypnograms
- Future peak protection logic

## Naming

As part of this work, `MontagePlayerView` will be renamed to `PreviewPlayerView` to better reflect its role. The "montage" terminology is a legacy of earlier architecture.

---

## Implementation Plan

### Phase 1: Extract ABPlayerCoordinator from LivePlayer

**Goal**: Create a reusable coordinator that manages two AVPlayers and handles transitions.

**New file**: `Hypnograph/Dream/ABPlayerCoordinator.swift`

The coordinator:
- Owns two AVPlayer instances (A/B)
- Tracks active slot
- Provides transition API with style, duration, callbacks
- Handles playback control forwarding
- Manages player lifecycle and cleanup

### Phase 2: Create HypnogramPlayer

**Goal**: Build the shared player class that both Preview and Live will use.

**New file**: `Hypnograph/Dream/HypnogramPlayer.swift`

The player:
- Owns ABPlayerCoordinator
- Handles composition building via RenderEngine
- Manages transition settings
- Provides callbacks for time, clip end, boundaries
- Handles observer management

### Phase 3: Migrate LivePlayer to use HypnogramPlayer

LivePlayer becomes a thin wrapper around HypnogramPlayer, keeping only:
- Window management
- Screen selection
- Independent effect manager

### Phase 4: Migrate MontagePlayerView to PreviewPlayerView

Rename and refactor to use HypnogramPlayer:
- SwiftUI bindings remain
- Time observer handled by HypnogramPlayer
- A/B views managed by coordinator

### Phase 5: Add Transition Settings

User-configurable transition style and duration in Settings and PlayerSettingsView.

### Phase 6: Implement Punk Transition Style

Add the jittery/stepped "punk" transition aesthetic using keyframe animation.

### Phase 7: Boundary Hooks for Volume Leveling

Provide stable integration points for the volume leveling project via callbacks.

## Success Criteria

- Preview and Live both use HypnogramPlayer internally
- Transitions work identically in both contexts
- All existing Preview functionality preserved
- All existing Live functionality preserved
- Boundary hooks in place for volume leveling integration
- No regression in playback smoothness or memory usage
