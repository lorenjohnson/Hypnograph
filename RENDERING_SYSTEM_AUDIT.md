# Hypnograph Rendering System Audit

## Executive Summary

The rendering system is built on AVFoundation with custom compositing via `AVVideoCompositing`. It supports two modes (montage and sequence), live preview with effects, and export to disk. The architecture is sound and has been enhanced with a GPU-efficient frame buffer system.

**Key Findings (Updated):**
1. ✅ Unified code path for preview/export
2. ✅ **NEW**: GPU-efficient 120-frame ring buffer (CVPixelBuffer/IOSurface)
3. ✅ **NEW**: Shared CIContext across all components (SharedRenderer)
4. ✅ **NEW**: Effects declare `requiredLookback` for filtering/optimization
5. ⚠️ GlobalRenderHooks singleton creates tight coupling (acceptable for AVFoundation bridge)
6. ⚠️ No frame dropping/throttling for performance under load
7. ⚠️ FrameProcessor is largely unused (duplicate of FrameCompositor logic)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        HypnographState                          │
│  (owns: HypnogramRecipe, RenderHookManager)                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      RenderHookManager                          │
│  - Recipe access via closures (recipeProvider, effectsSetter)   │
│  - FrameBuffer (60 frames, baked CGImages)                      │
│  - Blend normalization                                          │
│  - Flash solo state                                             │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌──────────────────────┐        ┌──────────────────────────┐
│   PREVIEW PATH       │        │     EXPORT PATH          │
│                      │        │                          │
│  RenderEngine        │        │  RenderEngine            │
│      ▼               │        │      ▼                   │
│  CompositionBuilder  │        │  CompositionBuilder      │
│  (isExport: false)   │        │  (isExport: true)        │
│      ▼               │        │      ▼                   │
│  AVPlayerItem        │        │  AVAssetExportSession    │
│      ▼               │        │      ▼                   │
│  FrameCompositor     │        │  FrameCompositor         │
│  (GlobalRenderHooks) │        │  (dedicated manager)     │
└──────────────────────┘        └──────────────────────────┘
```

---

## Data Flow: Preview

1. **Recipe Creation**: `HypnographState` builds `HypnogramRecipe` with sources, effects, blend modes
2. **Composition Build**: `RenderEngine.makePlayerItem()` → `CompositionBuilder.build()`:
   - Creates `AVMutableComposition` with video/audio tracks
   - Creates `RenderInstruction` with layer info (no recipeSnapshot for preview)
   - Creates `AVMutableVideoComposition` with instructions
3. **Playback**: `AVPlayer` drives playback, AVFoundation calls `FrameCompositor`
4. **Frame Rendering**: `FrameCompositor.renderFrame()`:
   - Detects preview (recipeSnapshot == nil) → uses `GlobalRenderHooks.manager`
   - For each layer: get frame, apply transform, aspect-fill, apply per-source effects
   - Blend layers with opacity compensation
   - Apply normalization
   - Apply global effects
   - Store frame in buffer
   - Render to output buffer

---

## Data Flow: Export

1. **Recipe Snapshot**: `RenderEngine.export()` calls `CompositionBuilder.build(isExport: true)`
   - Bakes `recipe` into `RenderInstruction.recipeSnapshot`
2. **Export Session**: Creates `AVAssetExportSession` with the video composition
3. **Frame Rendering**: `FrameCompositor.renderFrame()`:
   - Detects export (recipeSnapshot != nil) → creates dedicated `RenderHookManager.forExport(recipe:)`
   - Same rendering logic as preview, but isolated state
   - Frame buffer starts empty, frame counter starts at 0

---

## Component Analysis

### RenderHookManager (514 lines)

**Purpose**: Central orchestrator for effects, blend modes, normalization, frame buffer.

**Responsibilities** (too many?):
- Recipe access via closures
- Frame buffer management
- Frame counter
- Global effect management
- Per-source effect management
- Blend mode management
- Blend normalization strategy
- Flash solo state
- Effect change notifications

**Issues**:
- Closure-based recipe access is indirect (but necessary for decoupling)
- `applyGlobal()` adds frame to buffer even when not using temporal effects
- Factory method `forExport()` works but feels bolted-on

### FrameBuffer (91 lines)

**Purpose**: Circular buffer of recent frames for temporal effects.

**Good**:
- Now bakes CIImages to CGImages (fixed performance issue)
- Thread-safe with dispatch queue
- Detects seek/loop and clears

**Issues**:
- Creates its own CIContext (could share with compositor)
- 60 frames at 1080p ≈ 475MB memory (CGImages are uncompressed)
- No memory pressure handling

### FrameCompositor (238 lines)

**Purpose**: AVVideoCompositing implementation - the core per-frame renderer.

**Good**:
- Metal-backed CIContext
- Unified preview/export code path
- Proper error handling

**Issues**:
- Creates `exportManager` lazily but never cleans it up
- Captures `self` strongly in async block (documented but concerning)
- No frame timing/throttling - always renders at full rate
- `renderQueue` is `.userInteractive` QoS (appropriate for preview, overkill for export)

### CompositionBuilder (408 lines)

**Purpose**: Builds AVMutableComposition from HypnogramRecipe.

**Good**:
- Clean separation of montage vs sequence logic
- Handles still images and videos
- Audio track handling

**Issues**:
- Large methods (buildMontage ~170 lines, buildSequence ~140 lines)
- Duplicate code between montage/sequence paths
- Creates multiple instructions for sequence (one per clip) but single for montage

### FrameProcessor (205 lines)

**Purpose**: "Unified frame processing pipeline for both preview and export"

**Issue**: **LARGELY UNUSED**. Only used by `MetalImageView` for still image display.
`FrameCompositor` duplicates most of this logic. Should consolidate.

### MetalImageView (224 lines)

**Purpose**: Direct Metal rendering for still images (bypasses AVPlayer).

**Good**:
- Proper Metal setup
- Supports animation via display link

**Issues**:
- Only used for still images in sequence mode
- Could share CIContext with compositor

---

## Performance Analysis

### Current Bottlenecks

1. **Frame Buffer Baking** (now fixed):
   - Each frame is rendered to CGImage before storage
   - Cost: ~1-2ms per frame at 1080p
   - Benefit: Prevents exponential filter chain growth

2. **No Frame Dropping**:
   - If rendering takes longer than frame interval (33ms at 30fps), frames back up
   - AVFoundation will eventually timeout requests
   - No graceful degradation

3. **Multiple CIContexts**:
   - `FrameCompositor` creates one
   - `FrameBuffer` creates one
   - `MetalImageView` creates one
   - `FrameProcessor` creates one
   - Each context has Metal overhead

4. **Blend Normalization**:
   - Runs every frame even when not needed
   - Analysis is cached but still checked every frame

5. **Recipe Provider Calls**:
   - `recipeProvider?()` called multiple times per frame
   - Could cache per-frame

### Memory Concerns

1. **Frame Buffer**: 60 × 1080p CGImages ≈ 475MB worst case
2. **CIImage Filter Chains**: Now fixed by baking
3. **Still Images in Instructions**: `RenderInstruction.stillImages` holds CIImages

---

## Simplification Opportunities

### 1. Eliminate FrameProcessor or Consolidate

`FrameProcessor` and `FrameCompositor` do the same thing. Options:
- **A)** Delete FrameProcessor, have MetalImageView use FrameCompositor directly
- **B)** Extract shared logic into a pure function module
- **Recommendation**: Option B - create `RenderPipeline` with pure functions

### 2. Reduce GlobalRenderHooks Coupling

Current: `GlobalRenderHooks.manager` is a static singleton accessed from FrameCompositor.

Better: Pass manager through instruction or composition context.

**Problem**: AVFoundation creates FrameCompositor instances - we can't inject dependencies.

**Pragmatic solution**: Keep GlobalRenderHooks but document it as "AVFoundation bridge".

### 3. Share CIContext

Create a single shared CIContext (Metal-backed) and pass it through:
```swift
enum SharedRenderer {
    static let ciContext: CIContext = {
        let device = MTLCreateSystemDefaultDevice()!
        return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
    }()
}
```

### 4. Simplify RenderHookManager

Split into focused components:
- `FrameBufferManager` - just the buffer and frame counter
- `EffectRouter` - applies effects from recipe
- `BlendNormalizer` - blend analysis and compensation
- `RenderHookManager` - thin coordinator

**Trade-off**: More files, but each is simpler and testable.

### 5. Remove Duplicate Data in RenderInstruction

`RenderInstruction` stores:
- `blendModes` - also in recipe
- `transforms` - also (partially) in recipe

These are needed for export (frozen state), but for preview they're redundant.
Could have two instruction types or make optional.

---

## Performance Improvement Recommendations

### 1. Frame Dropping Under Load

Add frame timing and skip frames when behind:
```swift
private var lastFrameTime: CFAbsoluteTime = 0
private let targetFrameInterval: CFAbsoluteTime = 1.0 / 30.0

func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
    let now = CFAbsoluteTimeGetCurrent()
    let elapsed = now - lastFrameTime
    
    // If we're more than 2 frames behind, skip this one
    if elapsed < targetFrameInterval * 0.5 {
        request.finish(withComposedVideoFrame: /* last good buffer */)
        return
    }
    lastFrameTime = now
    // ... normal rendering
}
```

### 2. Reduce Frame Buffer Size Dynamically

Most effects only need 3-10 frames. Reduce default:
```swift
let frameBuffer = FrameBuffer(maxFrames: 15)  // 0.5s instead of 2s
```

Or make it configurable based on active effect.

### 3. Cache Recipe Per Frame

```swift
private var cachedRecipe: HypnogramRecipe?
private var cachedRecipeFrame: Int = -1

func getRecipe(forFrame frame: Int) -> HypnogramRecipe? {
    if frame == cachedRecipeFrame, let cached = cachedRecipe {
        return cached
    }
    cachedRecipe = recipeProvider?()
    cachedRecipeFrame = frame
    return cachedRecipe
}
```

### 4. Lazy Blend Analysis

Only compute when blend modes actually change:
```swift
private var cachedAnalysis: BlendModeAnalysis?
private var blendModeHash: Int = 0

var currentBlendAnalysis: BlendModeAnalysis {
    let modes = collectBlendModes()
    let hash = modes.hashValue
    if hash != blendModeHash {
        blendModeHash = hash
        cachedAnalysis = analyzeBlendModes(modes)
    }
    return cachedAnalysis!
}
```

### 5. Lower Export QoS

```swift
// In FrameCompositor, detect export and use lower QoS
let qos: DispatchQoS = isExport ? .utility : .userInteractive
renderQueue = DispatchQueue(label: "...", qos: qos)
```

---

## Recommendations Summary

### High Priority (Do Now)
1. **Add frame dropping** - prevents stuttering under load
2. **Share CIContext** - reduce memory/GPU overhead
3. **Reduce frame buffer default** - 60 frames is excessive

### Medium Priority (Next Sprint)
1. **Delete or consolidate FrameProcessor** - reduce code duplication
2. **Cache recipe per frame** - avoid repeated closure calls
3. **Lower export QoS** - don't compete with preview

### Low Priority (Future)
1. **Split RenderHookManager** - better separation of concerns
2. **Create proper injection for GlobalRenderHooks** - cleaner architecture
3. **Add memory pressure handling** - reduce buffer on low memory

---

## Appendix: File Inventory

| File | Lines | Purpose | Health |
|------|-------|---------|--------|
| RenderHooks.swift | 514 | Effects system, manager, buffer | ⚠️ Large |
| CompositionBuilder.swift | 408 | Build AVComposition | ⚠️ Large methods |
| BlendModes.swift | 278 | Blend constants, normalization | ✅ Good |
| FrameCompositor.swift | 238 | AVVideoCompositing impl | ✅ Good |
| MetalImageView.swift | 224 | Still image display | ✅ Good |
| RenderEngine.swift | 214 | Preview/export orchestration | ✅ Good |
| FrameProcessor.swift | 205 | Frame processing (unused?) | ❌ Redundant |
| ImageUtils.swift | 125 | Aspect fill, blending | ✅ Good |
| RenderInstruction.swift | 86 | Composition instruction | ✅ Good |
| HypnogramRenderer.swift | 86 | Export wrapper | ✅ Good |

**Total**: ~2,378 lines in core rendering system

