# Metal Playback Pipeline: Implementation Plan (Direction A)

**Created**: 2026-01-18
**Updated**: 2026-01-18
**Status**: Core Implementation Complete - Integration Pending
**Approach**: AVPlayerItemVideoOutput + MTKView

## Implementation Progress

| Phase | Status | Notes |
|-------|--------|-------|
| 1. MetalPlayerView foundation | ✅ Complete | MTKView + Passthrough shader |
| 2. AVPlayerFrameSource + TextureCache | ✅ Complete | FrameSource protocol, YUV support |
| 3. YUV→RGB conversion | ✅ Complete | BT.709/BT.601, video/full range |
| 4. Effect pipeline integration | ✅ Complete | Kept in AVVideoComposition |
| 5. TransitionRenderer | ✅ Complete | 7 transition types |
| 6. Dual-source transitions | ✅ Complete | Built into MetalPlayerView |
| 7. PreviewPlayerView integration | 🔲 Pending | MetalPlayerController ready |
| 8. LivePlayer integration | 🔲 Pending | Requires Phase 7 first |
| 9. Cleanup and polish | 🔲 Pending | After integration testing |

---

This document details the implementation plan for Direction A: using AVPlayer for decode/sync while rendering through a unified Metal surface.

---

## Current State Analysis

### What We Have Now

| Component | Implementation |
|-----------|----------------|
| **PreviewPlayerView** | `NSViewRepresentable` wrapping `AVPlayerView` |
| **LivePlayer** | Two `AVPlayer` instances with alpha crossfade |
| **FrameCompositor** | `AVVideoCompositing` implementation for per-frame effects |
| **Effect Pipeline** | CIImage-based with Metal shaders via `MetalEffect` base class |
| **Texture Cache** | `CVMetalTextureCache` exists in `MetalEffect` for effect processing |
| **Frame Buffer** | IOSurface-backed `CVPixelBuffer` pool for temporal effects |

### Current Data Flow

```
HypnogramClip
    ↓
RenderEngine.makePlayerItem()
    ↓
AVComposition + AVVideoComposition (customVideoCompositorClass = FrameCompositor)
    ↓
AVPlayer → AVPlayerView (owns display)
```

### What Changes

```
HypnogramClip
    ↓
RenderEngine.makePlayerItem() (same)
    ↓
AVComposition + AVVideoComposition + FrameCompositor (same)
    ↓
AVPlayer + AVPlayerItemVideoOutput (NEW: pull frames)
    ↓
CVMetalTextureCache → MTLTexture (NEW)
    ↓
MetalPlayerView (MTKView) (NEW: we own display)
    ↓
TransitionRenderer (shader transitions) (NEW)
```

---

## Implementation Phases

### Phase 1: MetalPlayerView Foundation

**Goal**: Create MTKView subclass that can render a test texture, wired to DisplayLink.

**New Files**:
- `HypnoCore/Renderer/Display/MetalPlayerView.swift`

**Implementation**:

```swift
// MetalPlayerView.swift
import MetalKit
import AVFoundation

final class MetalPlayerView: MTKView {
    private var commandQueue: MTLCommandQueue?
    private var renderPipelineState: MTLRenderPipelineState?
    private var currentTexture: MTLTexture?

    // Thread-safe texture swap
    private let textureLock = NSLock()

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device ?? SharedRenderer.device)
        configure()
    }

    private func configure() {
        guard let device = self.device else { return }

        commandQueue = device.makeCommandQueue()
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60

        setupRenderPipeline()
    }

    func setTexture(_ texture: MTLTexture?) {
        textureLock.lock()
        currentTexture = texture
        textureLock.unlock()
    }

    override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let descriptor = currentRenderPassDescriptor else { return }

        textureLock.lock()
        let texture = currentTexture
        textureLock.unlock()

        // Render texture to drawable (or clear to black if nil)
        renderTexture(texture, to: drawable, descriptor: descriptor, commandBuffer: commandBuffer)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
```

**Tasks**:
1. Create `MetalPlayerView` class with basic MTKView setup
2. Add render pipeline for texture-to-screen blit (simple passthrough shader)
3. Add `Passthrough.metal` shader for texture rendering
4. Wire up to SharedRenderer.device for GPU resource sharing
5. Create test harness: display solid color, then static image

**Verification**:
- [ ] MetalPlayerView renders solid color
- [ ] MetalPlayerView renders static MTLTexture
- [ ] Frame rate matches display refresh (60fps)

---

### Phase 2: AVPlayerItemVideoOutput Integration

**Goal**: Pull CVPixelBuffer frames from AVPlayer and display in MetalPlayerView.

**New Files**:
- `HypnoCore/Renderer/FrameSource/FrameSource.swift` (protocol)
- `HypnoCore/Renderer/FrameSource/AVPlayerFrameSource.swift`
- `HypnoCore/Renderer/FrameSource/TextureCache.swift`

**FrameSource Protocol**:

```swift
// FrameSource.swift
import CoreMedia
import CoreVideo

struct DecodedFrame {
    let pixelBuffer: CVPixelBuffer
    let pts: CMTime
    let duration: CMTime?
    let isKeyframe: Bool
    let colorSpace: CGColorSpace?
}

protocol FrameSource: AnyObject {
    /// Prepare for playback around this time (hint for pre-roll)
    func prepare(at time: CMTime)

    /// Get the best available frame for the target PTS
    func bestFrame(for targetPTS: CMTime) -> DecodedFrame?

    /// Current playback time (for sync)
    var currentTime: CMTime { get }

    /// Whether source is ready to provide frames
    var isReady: Bool { get }
}
```

**AVPlayerFrameSource Implementation**:

```swift
// AVPlayerFrameSource.swift
final class AVPlayerFrameSource: FrameSource {
    private let player: AVPlayer
    private var videoOutput: AVPlayerItemVideoOutput?
    private let outputSettings: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelBufferMetalCompatibilityKey as String: true
    ]

    var currentTime: CMTime {
        player.currentTime()
    }

    var isReady: Bool {
        videoOutput?.hasNewPixelBuffer(forItemTime: currentTime) ?? false
    }

    func bestFrame(for targetPTS: CMTime) -> DecodedFrame? {
        guard let output = videoOutput else { return nil }

        var actualTime = CMTime.zero
        guard let buffer = output.copyPixelBuffer(forItemTime: targetPTS, itemTimeForDisplay: &actualTime) else {
            return nil
        }

        return DecodedFrame(
            pixelBuffer: buffer,
            pts: actualTime,
            duration: nil,
            isKeyframe: false,  // AVPlayer doesn't expose this
            colorSpace: CVImageBufferGetColorSpace(buffer)
        )
    }

    func attachOutput(to playerItem: AVPlayerItem) {
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        playerItem.add(output)
        self.videoOutput = output
    }
}
```

**TextureCache Wrapper**:

```swift
// TextureCache.swift
final class TextureCache {
    private var cache: CVMetalTextureCache?
    private let device: MTLDevice

    init(device: MTLDevice = SharedRenderer.device) {
        self.device = device
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
    }

    /// Convert CVPixelBuffer to Metal textures (Y + CbCr for YUV content)
    func textures(from pixelBuffer: CVPixelBuffer) -> (y: MTLTexture, cbcr: MTLTexture)? {
        guard let cache = cache else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Y plane (full resolution)
        var yTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .r8Unorm, width, height, 0, &yTexture
        )

        // CbCr plane (half resolution)
        var cbcrTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .rg8Unorm, width / 2, height / 2, 1, &cbcrTexture
        )

        guard let y = yTexture, let cbcr = cbcrTexture,
              let yMetal = CVMetalTextureGetTexture(y),
              let cbcrMetal = CVMetalTextureGetTexture(cbcr) else {
            return nil
        }

        return (yMetal, cbcrMetal)
    }

    /// Single-plane BGRA texture (for RGBA content or post-conversion)
    func texture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = cache else { return nil }

        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            0, &cvTexture
        )

        guard let tex = cvTexture else { return nil }
        return CVMetalTextureGetTexture(tex)
    }

    func flush() {
        guard let cache = cache else { return }
        CVMetalTextureCacheFlush(cache, 0)
    }
}
```

**Tasks**:
1. Create `FrameSource` protocol and `DecodedFrame` struct
2. Implement `AVPlayerFrameSource` wrapping AVPlayer + AVPlayerItemVideoOutput
3. Implement `TextureCache` for CVPixelBuffer → MTLTexture conversion
4. Add YUV bi-planar support (420YpCbCr8BiPlanarVideoRange)
5. Wire AVPlayerFrameSource to existing AVPlayer in PreviewPlayerView
6. Feed frames to MetalPlayerView on display tick

**Verification**:
- [ ] AVPlayerItemVideoOutput provides frames at display rate
- [ ] CVPixelBuffer converts to MTLTexture without copy (IOSurface backed)
- [ ] Video displays in MetalPlayerView (may look wrong until YUV→RGB)

---

### Phase 3: YUV→RGB and Basic Rendering

**Goal**: Proper color conversion in Metal shader, basic single-source display.

**New Files**:
- `HypnoCore/Renderer/Shaders/YUVConversion.metal`

**YUV Conversion Shader**:

```metal
// YUVConversion.metal
#include <metal_stdlib>
using namespace metal;

// BT.709 YUV to RGB conversion matrix
constant float3x3 yuvToRGB = float3x3(
    float3(1.0,  1.0,      1.0),
    float3(0.0, -0.18732, 1.8556),
    float3(1.5748, -0.46812, 0.0)
);

kernel void yuvToRGBA(
    texture2d<float, access::read> yTexture [[texture(0)]],
    texture2d<float, access::read> cbcrTexture [[texture(1)]],
    texture2d<float, access::write> outTexture [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float y = yTexture.read(gid).r;
    float2 cbcr = cbcrTexture.read(gid / 2).rg;

    // Convert from video range [16-235] to full range [0-1]
    y = (y - 16.0/255.0) * (255.0/219.0);
    float cb = cbcr.r - 0.5;
    float cr = cbcr.g - 0.5;

    float3 yuv = float3(y, cb, cr);
    float3 rgb = yuvToRGB * yuv;

    outTexture.write(float4(saturate(rgb), 1.0), gid);
}
```

**Tasks**:
1. Create YUV→RGB Metal compute shader (BT.709)
2. Add full-range vs video-range handling
3. Integrate into MetalPlayerView render loop
4. Profile: ensure conversion doesn't add latency

**Verification**:
- [ ] Colors appear correct (no green/purple tint)
- [ ] Video range content displays correctly
- [ ] Full range content displays correctly

---

### Phase 4: Effect Pipeline Integration

**Goal**: Apply existing FrameCompositor effects through Metal pipeline.

**Approach**: The existing `FrameCompositor` runs as part of `AVVideoComposition`. With Direction A, we have two options:

**Option A (Recommended)**: Keep FrameCompositor in AVVideoComposition
- AVPlayer still uses AVVideoComposition with FrameCompositor
- AVPlayerItemVideoOutput pulls post-composited frames
- Effects already applied; MetalPlayerView just displays
- **Minimal change to effect pipeline**

**Option B**: Move effects to MetalPlayerView render loop
- Pull raw frames before composition
- Apply effects in MetalPlayerView draw loop
- More control but significant refactor

**For Phase 4, use Option A**:

```swift
// In AVPlayerFrameSource setup
func configure(with clip: HypnogramClip, effectManager: EffectManager) async throws {
    // Build composition with FrameCompositor (existing code)
    let (composition, videoComposition) = try await CompositionBuilder.build(
        clip: clip,
        effectManager: effectManager
    )

    // Set custom compositor (existing)
    videoComposition.customVideoCompositorClass = FrameCompositor.self

    // Create player item
    let playerItem = AVPlayerItem(asset: composition)
    playerItem.videoComposition = videoComposition

    // Attach video output for frame pulling
    attachOutput(to: playerItem)

    // Load into player
    player.replaceCurrentItem(with: playerItem)
}
```

**Tasks**:
1. Verify AVPlayerItemVideoOutput works with custom AVVideoComposition
2. Ensure FrameCompositor output is what VideoOutput provides
3. Test multi-source compositing displays correctly
4. Test per-source and global effects render correctly
5. Verify temporal effects (frame history) still work

**Verification**:
- [ ] Multi-layer compositing displays correctly
- [ ] Blend modes work as expected
- [ ] Per-source effects apply
- [ ] Global effects apply
- [ ] Temporal effects (echo, datamosh) work

---

### Phase 5: Transition Renderer

**Goal**: Shader-based transitions between two textures.

**New Files**:
- `HypnoCore/Renderer/Transitions/TransitionRenderer.swift`
- `HypnoCore/Renderer/Shaders/Transitions.metal`

**TransitionRenderer**:

```swift
// TransitionRenderer.swift
final class TransitionRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineStates: [TransitionType: MTLComputePipelineState] = [:]

    enum TransitionType: String, CaseIterable {
        case crossfade
        case punk       // Stepped/jittery blend
        case wipeLeft
        case wipeRight
        case wipeUp
        case wipeDown
    }

    struct TransitionParams {
        var progress: Float      // 0.0 → 1.0
        var direction: Float     // For directional transitions
        var seed: UInt32         // For randomized transitions
    }

    func render(
        outgoing: MTLTexture,
        incoming: MTLTexture,
        output: MTLTexture,
        type: TransitionType,
        progress: Float,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let pipeline = pipelineStates[type],
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(outgoing, index: 0)
        encoder.setTexture(incoming, index: 1)
        encoder.setTexture(output, index: 2)

        var params = TransitionParams(progress: progress, direction: 0, seed: 0)
        encoder.setBytes(&params, length: MemoryLayout<TransitionParams>.size, index: 0)

        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (output.width + 15) / 16,
            height: (output.height + 15) / 16,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
    }
}
```

**Transition Shaders**:

```metal
// Transitions.metal
#include <metal_stdlib>
using namespace metal;

struct TransitionParams {
    float progress;
    float direction;
    uint seed;
};

kernel void crossfade(
    texture2d<float, access::read> outgoing [[texture(0)]],
    texture2d<float, access::read> incoming [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant TransitionParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float4 a = outgoing.read(gid);
    float4 b = incoming.read(gid);
    output.write(mix(a, b, params.progress), gid);
}

kernel void punk(
    texture2d<float, access::read> outgoing [[texture(0)]],
    texture2d<float, access::read> incoming [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant TransitionParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Quantize progress to create stepped effect
    float steps = 8.0;
    float quantized = floor(params.progress * steps) / steps;

    // Add per-pixel noise for jitter
    float noise = fract(sin(dot(float2(gid), float2(12.9898, 78.233))) * 43758.5453);
    float threshold = quantized + (noise - 0.5) * 0.1;

    float4 a = outgoing.read(gid);
    float4 b = incoming.read(gid);
    output.write(params.progress > threshold ? b : a, gid);
}

kernel void wipe(
    texture2d<float, access::read> outgoing [[texture(0)]],
    texture2d<float, access::read> incoming [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant TransitionParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float normalized = float(gid.x) / float(outgoing.get_width());
    float edge = params.progress;
    float softness = 0.02;
    float blend = smoothstep(edge - softness, edge + softness, normalized);

    float4 a = outgoing.read(gid);
    float4 b = incoming.read(gid);
    output.write(mix(a, b, blend), gid);
}
```

**Tasks**:
1. Create `TransitionRenderer` class
2. Implement crossfade shader
3. Implement punk (stepped/jittery) shader
4. Implement directional wipe shaders
5. Add transition progress animation driver
6. Integrate with MetalPlayerView

**Verification**:
- [ ] Crossfade transitions smoothly
- [ ] Punk transition has visible stepping
- [ ] Wipe transitions reveal in correct direction
- [ ] No visual artifacts at transition boundaries

---

### Phase 6: Dual-Source Transitions

**Goal**: Handle transitions between two clips with two AVPlayers.

**Modified Files**:
- `HypnoCore/Renderer/Display/MetalPlayerView.swift`

**Architecture**:

```swift
// MetalPlayerView additions
final class MetalPlayerView: MTKView {
    // Two frame sources for transitions
    private var primarySource: AVPlayerFrameSource?
    private var secondarySource: AVPlayerFrameSource?

    // Transition state
    private var transitionProgress: Float = 0
    private var transitionType: TransitionRenderer.TransitionType?
    private var transitionStartTime: CFTimeInterval?
    private var transitionDuration: CFTimeInterval = 1.5

    private let transitionRenderer = TransitionRenderer()
    private let textureCache = TextureCache()

    func startTransition(
        to newSource: AVPlayerFrameSource,
        type: TransitionRenderer.TransitionType,
        duration: CFTimeInterval
    ) {
        secondarySource = newSource
        transitionType = type
        transitionDuration = duration
        transitionStartTime = CACurrentMediaTime()
    }

    override func draw(_ rect: CGRect) {
        // ... existing setup ...

        // Get current frames
        let primaryFrame = primarySource?.bestFrame(for: primarySource?.currentTime ?? .zero)
        let primaryTexture = primaryFrame.flatMap { textureCache.texture(from: $0.pixelBuffer) }

        // Check if transitioning
        if let startTime = transitionStartTime,
           let type = transitionType,
           let secondarySource = secondarySource {

            let elapsed = CACurrentMediaTime() - startTime
            transitionProgress = Float(min(elapsed / transitionDuration, 1.0))

            let secondaryFrame = secondarySource.bestFrame(for: secondarySource.currentTime)
            let secondaryTexture = secondaryFrame.flatMap { textureCache.texture(from: $0.pixelBuffer) }

            if let outgoing = primaryTexture, let incoming = secondaryTexture {
                // Render transition
                transitionRenderer.render(
                    outgoing: outgoing,
                    incoming: incoming,
                    output: outputTexture,
                    type: type,
                    progress: transitionProgress,
                    commandBuffer: commandBuffer
                )
            }

            // Complete transition
            if transitionProgress >= 1.0 {
                primarySource = secondarySource
                self.secondarySource = nil
                transitionStartTime = nil
                transitionType = nil
            }
        } else {
            // Normal rendering (no transition)
            renderTexture(primaryTexture, ...)
        }
    }
}
```

**Tasks**:
1. Add secondary frame source support to MetalPlayerView
2. Implement transition state machine (idle → transitioning → complete)
3. Pre-roll secondary source before transition starts
4. Handle audio crossfade (volume ramp on both players)
5. Clean up secondary source after transition completes

**Verification**:
- [ ] Transition from clip A to clip B works
- [ ] No black frames during transition
- [ ] Audio crossfades smoothly
- [ ] Memory cleaned up after transition

---

### Phase 7: PreviewPlayerView Integration

**Goal**: Replace AVPlayerView with MetalPlayerView in Preview.

**Modified Files**:
- `Hypnograph/Dream/MontagePlayerView.swift` → refactor to use MetalPlayerView

**Approach**:
- Create `NSViewRepresentable` wrapper for MetalPlayerView
- Maintain same external interface (clip, aspectRatio, volume, etc.)
- Internal implementation switches from AVPlayerView to MetalPlayerView

```swift
// PreviewPlayerView.swift (refactored)
struct PreviewPlayerView: NSViewRepresentable {
    // Same interface as before
    let clip: HypnogramClip
    let aspectRatio: AspectRatio
    // ...

    func makeNSView(context: Context) -> MetalPlayerView {
        let view = MetalPlayerView(frame: .zero, device: SharedRenderer.device)
        context.coordinator.setupPlayer(view: view)
        return view
    }

    func updateNSView(_ view: MetalPlayerView, context: Context) {
        context.coordinator.update(with: clip, config: ...)
    }

    class Coordinator {
        private var frameSource: AVPlayerFrameSource?
        private var player: AVPlayer?

        func setupPlayer(view: MetalPlayerView) {
            player = AVPlayer()
            frameSource = AVPlayerFrameSource(player: player!)
            // Wire frame source to view...
        }
    }
}
```

**Tasks**:
1. Create MetalPlayerView NSViewRepresentable wrapper
2. Migrate PreviewPlayerView to use MetalPlayerView internally
3. Maintain same external interface for Dream.swift
4. Handle still image sources (no AVPlayer needed)
5. Feature flag: ability to toggle between old/new implementation
6. Test all existing preview functionality

**Verification**:
- [ ] Preview displays video correctly
- [ ] Preview displays still images correctly
- [ ] Playback rate control works
- [ ] Volume control works
- [ ] Audio device routing works
- [ ] Looping works
- [ ] All effects work in preview

---

### Phase 8: LivePlayer Integration

**Goal**: Replace dual AVPlayerViews with single MetalPlayerView in Live.

**Modified Files**:
- `Hypnograph/Dream/LivePlayer.swift`
- `Hypnograph/Live/LiveContentView.swift` (or equivalent)

**Current LivePlayer Architecture**:
- Two AVPlayers (A and B)
- Two AVPlayerViews with alpha crossfade
- Manual view hierarchy management

**New Architecture**:
- Two AVPlayers (kept for decode/audio)
- Two AVPlayerFrameSources
- One MetalPlayerView with shader transitions

```swift
// LivePlayer.swift (refactored)
final class LivePlayer: ObservableObject {
    // Frame sources instead of player views
    private var sourceA: AVPlayerFrameSource?
    private var sourceB: AVPlayerFrameSource?
    private var activeSource: AVPlayerFrameSource? { isAActive ? sourceA : sourceB }

    // Single Metal view
    private var metalView: MetalPlayerView?

    func send(clip: HypnogramClip, config: DreamPlayerConfig) async throws {
        let inactiveSource = isAActive ? sourceB : sourceA

        // Build composition for inactive source
        try await inactiveSource?.configure(with: clip, effectManager: effectManager)

        // Start shader transition
        metalView?.startTransition(
            to: inactiveSource!,
            type: .crossfade,
            duration: 1.5
        )

        // Swap active
        isAActive.toggle()
    }
}
```

**Tasks**:
1. Refactor LivePlayer to use AVPlayerFrameSource
2. Replace view alpha transitions with shader transitions
3. Single MetalPlayerView for live display
4. Handle window management (fullscreen, external monitor)
5. Audio crossfade via player volume (existing approach)
6. Remove ABPlayerCoordinator complexity

**Verification**:
- [ ] Live displays on external monitor
- [ ] Live displays in windowed mode
- [ ] Transitions work without black flashes
- [ ] Audio crossfades correctly
- [ ] Effect mutations work during playback
- [ ] Window resize handled correctly

---

### Phase 9: Cleanup and Polish

**Goal**: Remove deprecated code, finalize architecture.

**Removals**:
- Old view-based transition code
- ABPlayerCoordinator (if exists)
- HypnogramPlayer (if superseded)
- Feature flags for old implementation

**Polish**:
- Error handling for frame source failures
- Graceful degradation if Metal unavailable
- Memory profiling during transitions
- Performance optimization pass

**Tasks**:
1. Remove deprecated transition code
2. Remove unused player management classes
3. Update architecture documentation
4. Performance profiling and optimization
5. Memory leak testing
6. Edge case testing (seek, rate change, source swap)

**Verification**:
- [ ] No dead code remains
- [ ] Memory usage stable during extended playback
- [ ] No frame drops under normal load
- [ ] All tests pass
- [ ] Documentation updated

---

## File Summary

### New Files (Created)

| File | Purpose | Phase |
|------|---------|-------|
| `HypnoCore/Renderer/Display/MetalPlayerView.swift` | MTKView display surface with YUV + transitions | 1,3,6 |
| `HypnoCore/Renderer/Display/Passthrough.metal` | Texture-to-screen vertex/fragment shaders | 1 |
| `HypnoCore/Renderer/Display/YUVConversion.metal` | YUV→RGB compute + fragment shaders | 3 |
| `HypnoCore/Renderer/Display/MetalPlayerController.swift` | AVPlayer-to-Metal bridge controller | 7 |
| `HypnoCore/Renderer/FrameSource/FrameSource.swift` | Protocol + DecodedFrame struct | 2 |
| `HypnoCore/Renderer/FrameSource/AVPlayerFrameSource.swift` | AVPlayer + VideoOutput wrapper | 2 |
| `HypnoCore/Renderer/FrameSource/TextureCache.swift` | CVMetalTextureCache wrapper (BGRA + YUV) | 2 |
| `HypnoCore/Renderer/Transitions/TransitionRenderer.swift` | Shader transition driver | 5 |
| `HypnoCore/Renderer/Transitions/Transitions.metal` | 7 transition compute shaders | 5 |

### Modified Files

| File | Change | Phase |
|------|--------|-------|
| `HypnoCore/Renderer/Core/SharedRenderer.swift` | Expose device, add command queue | 1 |
| `Hypnograph/Dream/MontagePlayerView.swift` | Wrap MetalPlayerView | 7 |
| `Hypnograph/Dream/LivePlayer.swift` | Use FrameSource + MetalPlayerView | 8 |
| `Hypnograph/Dream/Dream.swift` | Simplify player creation | 8 |

### Removed Files (Phase 9)

| File | Reason |
|------|--------|
| View-level transition code | Replaced by shader transitions |
| ABPlayerCoordinator | No longer needed with single surface |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| AVPlayerItemVideoOutput latency | Profile early; output pulls are typically < 1ms |
| YUV conversion artifacts | Test with various source formats; support multiple matrices |
| Memory during transitions | Two AVPlayers acceptable; profile to confirm |
| Effect pipeline breakage | Keep FrameCompositor in AVVideoComposition (Option A) |
| Display sync issues | Use CADisplayLink/CVDisplayLink for timing |

---

## Testing Strategy

### Unit Tests
- `TextureCache` YUV plane extraction
- `TransitionRenderer` shader output validation
- `AVPlayerFrameSource` frame timing accuracy

### Integration Tests
- Full playback pipeline with effects
- Transition between clips with different resolutions
- Audio sync verification

### Manual Tests
- Visual inspection of transitions
- Performance under load (multiple sources)
- Memory stability during extended sessions
- External monitor behavior

---

## Success Criteria

From overview.md:
- [ ] Single MTKView displays composited video with effects
- [ ] Transitions are smooth, no black flashes
- [ ] Preview and Live use same rendering code
- [ ] Simpler architecture (fewer abstractions than A/B player approach)
- [ ] Performance equal or better than current
- [ ] No regression in existing functionality
- [ ] FrameSource abstraction allows future Direction B swap if needed

---

## Open Decisions

1. **YUV vs BGRA output from VideoOutput**: Start with YUV for efficiency; fall back to BGRA if compatibility issues arise.

2. **Transition duration**: Currently hardcoded 1.5s in LivePlayer. Make configurable?

3. **Effect application location**: Phase 4 recommends keeping FrameCompositor in AVVideoComposition. Revisit if latency becomes an issue.

4. **HDR handling**: Defer to future work. Build color space plumbing but treat as SDR/BT.709 initially.
