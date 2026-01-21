# Unified Player Architecture: Overview

**Created**: 2026-01-16
**Status**: Proposal / Planning

## Goal

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

## Current Behavior

### LivePlayer (Live output)
- Uses two `AVPlayerView` instances (A/B) stacked in `LiveContentView`
- `performCrossfade` animates alpha between players over ~1.5s
- Audio is a hard cut (old player muted immediately, new starts at full volume)
- No protection against overlapping transitions
- Works well for its purpose but transition logic is not reusable

### MontagePlayerView (Preview)
- Single `AVPlayerView` with `AVPlayerItem` replacement
- Hard cut on clip change (composition rebuilds, item swaps)
- Rich SwiftUI integration: time bindings, pause state, effects counter
- Still-image clip handling with timer-based auto-advance
- Watch mode integration for auto-advance on clip end

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

### Hypnogram Transitions (docs/projects/20260116-hypnogram-transitions/)
This project provides the **foundation** for transitions. The transitions project defines:
- Transition styles (None, Crossfade, Punk)
- User-facing settings
- Duration controls

This project provides the **infrastructure** to implement those styles.

### Volume Leveling (docs/projects/20260116-volume-leveling/)
The `willTransition` / `didTransition` boundary hooks created here are the integration point for:
- Audio fades at clip boundaries
- Volume leveling gain ramps between hypnograms
- Future peak protection logic

## Naming

As part of this work, `MontagePlayerView` will be renamed to `PreviewPlayerView` to better reflect its role. The "montage" terminology is a legacy of earlier architecture.

## Success Criteria

- [ ] Preview and Live both use HypnogramPlayer internally
- [ ] Transitions work identically in both contexts
- [ ] All existing Preview functionality preserved (time binding, pause, effects redraw, watch mode, still-image handling)
- [ ] All existing Live functionality preserved (window management, audio routing, independent effects)
- [ ] Boundary hooks in place for volume leveling integration
- [ ] No regression in playback smoothness or memory usage
