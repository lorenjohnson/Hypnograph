# Metal Playback Pipeline: Overview

**Created**: 2026-01-17
**Status**: Planning / Decision Required
**Supersedes**: 20260116-unified-player-architecture (shelved)

## Goal

Replace AVPlayerView/A-B view transitions with a single Metal render surface (MTKView), shader-based transitions, and a cleaner frame pipeline. This eliminates the complexity of dual-player coordination while enabling smoother transitions and better control.

## Problem with Current Architecture

The AVPlayer-based approach has inherent limitations:

| Issue | Impact |
|-------|--------|
| Dual AVPlayers for transitions | Complex state management, frame buffer corruption |
| AVPlayer owns timing | Cannot precisely control frame advance or sync with external audio |
| CIImage conversion overhead | Metal effects must go CIImage → MTLTexture → back |
| View-level transitions | Alpha fade is coarse; cannot do per-pixel transitions |
| Separate display surfaces | Preview and Live have different view hierarchies |

The recent unified-player-architecture added 710 lines of complexity to manage A/B player transitions, effectManager factories, and frame buffer isolation. Despite this, issues persist (black screens, timing edge cases).

---

## Two Viable Directions

### Direction A: AVPlayerItemVideoOutput + MTKView

Use **AVPlayer** for decoding + audio + sync, but bypass `AVPlayerView`. Pull frames as `CVPixelBuffer` from `AVPlayerItemVideoOutput` on a display-timed loop (CVDisplayLink), convert to Metal textures via `CVMetalTextureCache`, then render in an `MTKView`.

**What it buys you:**
- A/V sync "just works" (inherit AVPlayer's hard-earned sync behavior)
- Removes view-layer complexity: one MTKView surface, shader transitions, no alpha fades
- Good for streaming/HLS, DRM, subtitle tracks if ever needed
- Fastest path to "no black flashes / no A-B AVPlayerViews"

**What it costs:**
- You do not truly own decode scheduling (AVPlayer decides what/when)
- Frame stepping / deterministic external sync is harder

**Transition strategy:**
- Single MTKView render surface
- Transition between two textures (outgoing/incoming) rather than two views
- Two AVPlayers each with VideoOutput during transition, or swap items with pre-roll

### Direction B: AVAssetReader + PlaybackClock + MTKView

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

## Decision Heuristics

### Choose Direction A if:
- You want the single-MTKView + shader transitions win **fast**, with minimal new failure modes
- A/V sync correctness matters more than owning decode
- Streaming/DRM/subtitles might matter
- The pain is mostly in view-level A/B transitions and rendering architecture

### Choose Direction B if:
- Owning the timeline is core to the product: deterministic stepping, external clock sync, tempo-based behaviors
- You're prepared to build/rebuild decode sessions and manage audio sync yourself
- You can constrain scope to local files you control (no DRM/streaming)

### Recommendation

**Implement Direction A first** to get the architectural win (single surface, shader transitions, no A/B views). Keep compositor/transition code isolated so Direction B can later replace the frame source if needed.

---

## Key Implementation Concerns

These apply to either direction but especially to Direction B.

### 1. Make frame timing PTS-first (not "assume fixed FPS")
- Do not drive frame selection purely off `1/30` or DisplayLink ticks
- Treat presentation timestamps (PTS) as authoritative
- Recommended frame type: `DecodedFrame { pixelBuffer, pts, duration?, isKeyframe }`
- PlaybackClock produces a target PTS; render chooses best decoded frame for that target

### 2. AVAssetReader seeks require rebuild (Direction B)
- Plan for `cancel + recreate` on seek
- Rate changes are "advance target PTS faster/slower + drop frames"
- Design VideoDecoder as a session object with cheap rebuild

### 3. Keyframe-aware pre-roll for good seeking/transitions
- On seek to time T: start from keyframe before T, decode+discard until T
- For transitions: pre-roll incoming clip before transition starts

### 4. Keep YUV surfaces when possible
- Prefer bi-planar 420 surfaces; don't eagerly convert to RGBA
- Use CVMetalTextureCache to create Y plane + CbCr plane textures
- Do YUV→RGB conversion in Metal shaders (compositor/transition)

### 5. Color management + HDR hooks
- Carry frame color metadata (primaries/transfer/range) forward
- Decide output color space; ensure MTKView layer and shader pipeline match
- Build the plumbing now even if treating everything as SDR/BT.709 initially

### 6. Decouple decode from render
Avoid "draw(in:) blocks on decode" as the only model.

Structure:
- DisplayLink tick: compute target PTS, pick best already-decoded frame, render immediately
- Decode queue: maintain small bounded buffer ahead, drop when behind, pause when full

### 7. Multi-source compositing constraints
- Multiple decoders at full tilt will saturate CPU
- Policy: "active" layers decode at full cadence, background layers freeze or update at reduced rate

### 8. Audio sync: choose a master clock explicitly
- **Audio-led clock** (best feel): audio render timeline is master; video chases audio time
- **Video-led clock**: your clock is master; schedule audio accordingly (harder)
- Direction A naturally wants audio-led (AVPlayer); Direction B must decide

### 9. Use a render target pool
- Ping-pong textures for compositor + transition stages
- Reuse fixed-format textures; avoid per-frame allocations

### 10. Isolate CIImage bridge if any effects remain
- If some effects still use CIImage, single bridge stage:
  - Input: MTLTexture → CIContext render-to-texture → Output: MTLTexture
- Do not sprinkle CI↔Metal conversions throughout pipeline

### 11. Add timing harness early
Log at runtime: target PTS, chosen frame PTS, drift, dropped frames, buffer occupancy.
Makes VFR/jitter bugs diagnosable.

---

## Architectural Abstraction (Keeps A and B Swappable)

Define a minimal interface used by compositor/renderer:

```swift
protocol FrameSource {
    /// Optional: hint to prepare frames around this time
    func prepare(at time: CMTime)

    /// Get the best available frame for the target PTS
    func bestFrame(for targetPTS: CMTime) -> DecodedFrame?

    /// Request decode/backfill around target
    func requestFrames(around targetPTS: CMTime)
}

struct DecodedFrame {
    let pixelBuffer: CVPixelBuffer
    let pts: CMTime
    let duration: CMTime?
    let isKeyframe: Bool
}
```

Renderer consumes `DecodedFrame` as textures + metadata; does not care whether frames came from AVPlayerItemVideoOutput or AVAssetReader.

---

## Proposed Architecture (Direction A)

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

### AVPlayerFrameSource (Direction A)
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
- Adapt to work with MTLTexture directly (YUV→RGB in shader)
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

## Migration Strategy (Direction A)

### Phase 1: MetalPlayerView Skeleton
- Create MTKView subclass that renders a test texture
- Add to Preview alongside existing player (hidden, feature flag)
- Wire up DisplayLink-driven draw loop

### Phase 2: AVPlayerItemVideoOutput Integration
- Add VideoOutput to existing AVPlayer
- Pull CVPixelBuffer at display cadence
- Convert to Metal textures via CVMetalTextureCache
- Render in MetalPlayerView

### Phase 3: Multi-Layer Compositing
- Adapt FrameCompositor for MTLTexture input/output
- Add YUV→RGB conversion in compositor shader
- Verify effects still work
- Handle multiple sources

### Phase 4: Transitions
- Implement TransitionRenderer
- During transition: two AVPlayers, each with VideoOutput
- Shader-based crossfade between textures
- Pre-roll incoming clip before transition starts

### Phase 5: Audio (mostly free with Direction A)
- AVPlayer handles audio sync
- Volume/device routing as before
- Audio crossfade: adjust volumes during transition

### Phase 6: Live Integration
- LivePlayer uses MetalPlayerView
- Remove LiveContentView/dual AVPlayerViews
- Window management unchanged

### Phase 7: Cleanup
- Remove view-level transition code
- Remove ABPlayerCoordinator, HypnogramPlayer
- Remove feature flag

---

## Open Questions

1. **CIImage effects path**: Some effects may still use CIImage. Keep single CIContext bridge stage? Or migrate all to pure Metal?

2. **Still-image handling**: Direct texture load, no decode loop needed.

3. **Memory during transitions**: Two AVPlayers + VideoOutputs during transition. Profile to ensure acceptable.

4. **HDR content**: Build color metadata plumbing now or defer?

5. **Direction B later?**: If deterministic timing becomes essential, how hard is the swap with FrameSource abstraction in place?

---

## Success Criteria

- [ ] Single MTKView displays composited video with effects
- [ ] Transitions are smooth, no black flashes
- [ ] Preview and Live use same rendering code
- [ ] Simpler architecture (fewer abstractions than A/B player approach)
- [ ] Performance equal or better than current
- [ ] No regression in existing functionality
- [ ] FrameSource abstraction allows future Direction B swap if needed

---

## Files (Estimated)

| New File | Purpose |
|----------|---------|
| `FrameSource.swift` | Protocol + DecodedFrame struct |
| `AVPlayerFrameSource.swift` | Direction A implementation |
| `TextureCache.swift` | CVMetalTextureCache wrapper |
| `TransitionRenderer.swift` | Metal shader transitions |
| `MetalPlayerView.swift` | MTKView display surface |
| `Transitions.metal` | Transition shaders |

| Modified File | Change |
|---------------|--------|
| `FrameCompositor.swift` | Add MTLTexture path, YUV→RGB shader |
| `PreviewPlayerView.swift` | Wrap MetalPlayerView instead of AVPlayerView |
| `LivePlayer.swift` | Use MetalPlayerView, simplify significantly |
| `Dream.swift` | Remove factory patterns, simplify clip loading |

---

## Related Projects

- **20260116-unified-player-architecture**: Shelved. This project supersedes that approach.
- **20260116-hypnogram-transitions**: Transitions will be implemented as Metal shaders in this project.
- **20260116-volume-leveling**: Audio crossfade becomes simpler with AVPlayer still handling audio.
