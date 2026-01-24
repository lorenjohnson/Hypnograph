# Metal Playback Pipeline

**Created**: 2026-01-17
**Updated**: 2026-01-21
**Status**: Complete (Direction A)
**Notes**: Direction B remains a future option; the current codebase uses Direction A.

## Overview

Replace AVPlayerView/A-B view transitions with a single Metal render surface (MTKView), shader-based transitions, and a cleaner frame pipeline. This eliminates the complexity of dual-player coordination while enabling smoother transitions and better control.

## Problem with Previous Architecture

The AVPlayer-based approach has inherent limitations:

| Issue | Impact |
|-------|--------|
| Dual AVPlayers for transitions | Complex state management, frame buffer corruption |
| AVPlayer owns timing | Cannot precisely control frame advance or sync with external audio |
| CIImage conversion overhead | Metal effects must go CIImage → MTLTexture → back |
| View-level transitions | Alpha fade is coarse; cannot do per-pixel transitions |
| Separate display surfaces | Preview and Live have different view hierarchies |

The unified-player-architecture added 710 lines of complexity to manage A/B player transitions, effectManager factories, and frame buffer isolation. Despite this, issues persist (black screens, timing edge cases).

---

## Two Viable Directions

### Direction A: AVPlayerItemVideoOutput + MTKView (Implemented)

Use **AVPlayer** for decoding + audio + sync, but bypass `AVPlayerView`. Pull frames as `CVPixelBuffer` from `AVPlayerItemVideoOutput` on a display-timed loop (CVDisplayLink), convert to Metal textures via `CVMetalTextureCache`, then render in an `MTKView`.

**What it buys you:**
- A/V sync "just works" (inherit AVPlayer's hard-earned sync behavior)
- Removes view-layer complexity: one MTKView surface, shader transitions, no alpha fades
- Good for streaming/HLS, DRM, subtitle tracks if ever needed
- Fastest path to "no black flashes / no A-B AVPlayerViews"

**What it costs:**
- You do not truly own decode scheduling (AVPlayer decides what/when)
- Frame stepping / deterministic external sync is harder

### Direction B: AVAssetReader + PlaybackClock + MTKView (Future Option)

Use **AVAssetReader** to pull frames/samples yourself. You own decode session lifecycle, buffering, frame selection, and timing (PlaybackClock). Convert frames to Metal textures and render in MTKView with shader transitions.

**What it buys you:**
- Full control over timing, pre-roll, buffering, frame dropping/holding
- Deterministic features: frame-accurate stepping, external sync (MIDI), time-warping
- Decoding and composition optimized as a coherent system

**What it costs:**
- Hard problems: seeking, VFR cadence, drift, audio sync, color/HDR correctness
- AVAssetReader is a linear reader: seek often means cancel+rebuild
- More code, more edge cases, more testing

---

## Architecture (Direction A)

```
┌─────────────────────────────────────────────────────────────────────┐
│                   Metal Playback Pipeline (Direction A)              │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────┐     ┌──────────────┐     ┌────────────────────────────┐
│  AVPlayer   │────▶│ VideoOutput  │────▶│     TextureCache           │
│             │     │              │     │                            │
│ Decode +    │     │ CVPixelBuffer│     │  CVMetalTextureCache       │
│ A/V sync    │     │ on demand    │     │  Y + CbCr plane textures   │
└─────────────┘     └──────────────┘     └─────────────┬──────────────┘
                                                       │
┌─────────────┐                          ┌─────────────▼──────────────┐
│ DisplayLink │─────────────────────────▶│     FrameCompositor        │
│             │                          │  (existing, adapted)       │
│ Timing tick │                          │                            │
│ Target PTS  │                          │  - Multi-layer compositing │
└─────────────┘                          │  - Blend modes             │
                                         │  - Effect chains           │
                                         │  - YUV→RGB in shader       │
                                         └─────────────┬──────────────┘
                                                       │
                                         ┌─────────────▼──────────────┐
                                         │   TransitionRenderer       │
                                         │                            │
                                         │  - Metal shader transitions │
                                         │  - Crossfade, wipe, etc.   │
                                         │  - Per-pixel blending      │
                                         └─────────────┬──────────────┘
                                                       │
                                         ┌─────────────▼──────────────┐
                                         │     MetalPlayerView        │
                                         │                            │
                                         │  MTKView subclass          │
                                         │  Single display surface    │
                                         │  Used by Preview & Live    │
                                         └────────────────────────────┘
```

---

## Components

### AVPlayerFrameSource
- Wraps AVPlayer + AVPlayerItemVideoOutput
- Conforms to `FrameSource` protocol
- Provides frames on demand via `copyPixelBuffer(forItemTime:)`
- Handles audio via AVPlayer natively

### TextureCache (CVMetalTextureCache)
- Converts CVPixelBuffer to MTLTexture with zero-copy when possible
- Creates Y plane + CbCr plane textures for YUV content
- Maintains texture pool for reuse

### FrameCompositor (existing, adapted)
- Already handles multi-layer compositing with blend modes
- Adapted to work with MTLTexture directly (YUV→RGB in shader)
- Effect chains continue to work (many are already Metal-based)
- Source framing (fill/fit) remains in place

### TransitionRenderer
- Metal compute/render shader for transitions
- Inputs: outgoing texture, incoming texture, progress (0→1)
- Outputs: blended texture
- Transition types as shader variants:
  - `crossfade` - linear alpha blend
  - `punk` - stepped/jittery blend
  - `wipe` - directional reveal

### MetalPlayerView
- MTKView subclass used by both Preview and Live
- DisplayLink-driven draw loop
- Pulls current frame, applies effects, renders
- Replaces dual AVPlayerViews entirely

---

## What Stays

| Component | Status |
|-----------|--------|
| FrameCompositor | Kept, minor adaptation for MTLTexture |
| EffectManager | Kept as-is |
| Effect pipeline | Kept (already Metal-based) |
| EffectChain, CIEffects | Kept (isolated bridge if needed) |
| HypnogramClip, Recipe | Kept as-is |
| Data models | Kept |
| UI (SwiftUI views) | Kept, swap AVPlayerView for MetalPlayerView |

## What Changes

| Current | New |
|---------|-----|
| AVPlayerView display | MTKView display |
| View alpha transitions | Shader transitions |
| A/B player coordination | Single-surface, texture-level transitions |
| Two AVPlayers always | Two AVPlayers only during transitions |

---

## Implementation Progress

| Phase | Status | Notes |
|-------|--------|-------|
| 1. PlayerView foundation | ✅ Complete | MTKView + passthrough shader |
| 2. AVPlayerFrameSource + TextureCache | ✅ Complete | FrameSource protocol, YUV support |
| 3. YUV→RGB conversion | ✅ Complete | BT.709/BT.601, video/full range |
| 4. Effect pipeline integration | ✅ Complete | Kept in AVVideoComposition |
| 5. TransitionRenderer | ✅ Complete | crossfade, blur, slide transitions |
| 6. Dual-source transitions | ✅ Complete | Built into PlayerView |
| 7. PreviewPlayerView integration | ✅ Complete | Uses PlayerContentView |
| 8. LivePlayer integration | ✅ Complete | Uses PlayerContentView + mirrors |
| 9. Cleanup and polish | ✅ Complete | Removed legacy AVPlayerView-based rendering path |

---

## Key Files

### HypnoCore

| File | Purpose |
|------|---------|
| `Renderer/Display/PlayerView.swift` | MTKView subclass for Metal rendering |
| `Renderer/FrameSource/FrameSource.swift` | Protocol + DecodedFrame struct |
| `Renderer/FrameSource/AVPlayerFrameSource.swift` | AVPlayer + VideoOutput wrapper |
| `Renderer/FrameSource/TextureCache.swift` | CVMetalTextureCache wrapper |
| `Renderer/Transitions/TransitionRenderer.swift` | Shader transition driver |
| `Renderer/Transitions/TransitionCommon.h` | Shared transition shader header |
| `Renderer/Transitions/Implementations/*.metal` | Individual transition shaders |
| `Renderer/Display/Passthrough.metal` | Passthrough vertex/fragment shaders |
| `Renderer/Display/YUVConversion.metal` | YUV→RGB conversion shaders |

### Hypnograph App

| File | Purpose |
|------|---------|
| `Dream/PlayerContentView.swift` | A/B player with shader transitions |
| `Dream/PreviewPlayerView.swift` | SwiftUI wrapper for preview display |
| `Dream/LivePlayer.swift` | Live output management |

---

## Transitions

Transition types implemented:

- **None**: instant cut
- **Crossfade** (`transitionCrossfade`): simple linear blend
- **Blur** (`transitionBlur`): blur-to-next
- **Slide Up** (`transitionSlideUp`): film-strip vertical slide
- **Slide Left** (`transitionSlideLeft`): film-strip horizontal slide

Each transition is a separate Metal compute shader in `Transitions/Implementations/`.

## Playback Behavior

- **Loop mode** (watchMode OFF): Clips loop continuously
- **Watch mode** (watchMode ON): Clips advance to next when finished
- During transitions, outgoing clip loops to maintain smooth visuals
- Playback end observers registered for all active players

---

## Key Implementation Concerns

### Make frame timing PTS-first
- Do not drive frame selection purely off `1/30` or DisplayLink ticks
- Treat presentation timestamps (PTS) as authoritative
- Recommended frame type: `DecodedFrame { pixelBuffer, pts, duration?, isKeyframe }`

### Keep YUV surfaces when possible
- Prefer bi-planar 420 surfaces; don't eagerly convert to RGBA
- Use CVMetalTextureCache to create Y plane + CbCr plane textures
- Do YUV→RGB conversion in Metal shaders

### Color management + HDR hooks
- Carry frame color metadata forward
- Decide output color space; ensure MTKView layer and shader pipeline match
- Build the plumbing now even if treating everything as SDR/BT.709 initially

### Decouple decode from render
- DisplayLink tick: compute target PTS, pick best already-decoded frame, render immediately
- Decode queue: maintain small bounded buffer ahead, drop when behind, pause when full

---

## Success Criteria

- [x] Single MTKView displays composited video with effects
- [x] Transitions are smooth, no black flashes
- [x] Preview and Live use same rendering code
- [x] Simpler architecture (fewer abstractions than A/B player approach)
- [x] Performance equal or better than current
- [x] No regression in existing functionality
- [x] FrameSource abstraction allows future Direction B swap if needed

---

## Related Projects

- **20260116-unified-player-architecture**: Shelved. This project supersedes that approach.
- **20260116-hypnogram-transitions**: Transitions implemented as Metal shaders in this project.
- **20260116-volume-leveling**: Audio crossfade becomes simpler with AVPlayer still handling audio.
