# Metal Playback Pipeline: Implementation Plan (Direction A)

**Created**: 2026-01-17
**Updated**: 2026-01-18
**Status**: Complete - In Testing
**Approach**: AVPlayerItemVideoOutput + MTKView

## Summary

Replaced AVPlayerView-based rendering with a unified Metal pipeline for both Preview and Live displays. Key benefits:

- Single MTKView surface per display (no view hierarchy for transitions)
- GPU-accelerated shader transitions (crossfade, shuffle)
- A/B player architecture for seamless clip changes
- Shared frame sources enable mirror views

## Architecture

```
HypnogramClip
    ↓
RenderEngine.makePlayerItem()
    ↓
AVComposition + AVVideoComposition + FrameCompositor (effects applied here)
    ↓
AVPlayer + AVPlayerItemVideoOutput (frame pulling)
    ↓
TextureCache → MTLTexture
    ↓
PlayerView (MTKView) ← TransitionRenderer (shader blending)
```

## Implementation Progress

| Phase | Status | Notes |
|-------|--------|-------|
| 1. PlayerView foundation | ✅ Complete | MTKView + passthrough shader |
| 2. AVPlayerFrameSource + TextureCache | ✅ Complete | FrameSource protocol, YUV support |
| 3. YUV→RGB conversion | ✅ Complete | BT.709/BT.601, video/full range |
| 4. Effect pipeline integration | ✅ Complete | Kept in AVVideoComposition |
| 5. TransitionRenderer | ✅ Complete | crossfade, shuffle transitions |
| 6. Dual-source transitions | ✅ Complete | Built into PlayerView |
| 7. PreviewPlayerView integration | ✅ Complete | Uses PlayerContentView |
| 8. LivePlayer integration | ✅ Complete | Uses PlayerContentView + mirrors |
| 9. Cleanup and polish | 🔄 In Progress | Removing legacy code |

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

## Transitions

Transition types implemented:

- **None**: instant cut
- **Crossfade** (`transitionCrossfade`): simple linear blend
- **Blur** (`transitionBlur`): blur-to-next
- **Dissolve** (`transitionDissolve`): noise dissolve
- **Slide Up** (`transitionSlideUp`): film-strip vertical slide
- **Slide Left** (`transitionSlideLeft`): film-strip horizontal slide
- **Shuffle** (`transitionShuffle`): datamosh/glitch tear

Each transition is a separate Metal compute shader in `Transitions/Implementations/`.

## Playback Behavior

- **Loop mode** (watchMode OFF): Clips loop continuously
- **Watch mode** (watchMode ON): Clips advance to next when finished
- During transitions, outgoing clip loops to maintain smooth visuals
- Playback end observers registered for all active players

## Known Issues / TODOs

- Transition settings UI is wired in Player Settings; remaining work is polish and stabilization.
- Logging is mostly informational; consider standardizing on a logger and reducing noisy prints once stable.
