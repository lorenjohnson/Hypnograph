# Effects Architecture Refactor

## Goal

Split `RenderHooks.swift` (1500+ lines) into logical files with clean layer separation.
Use `Effect` naming throughout (not `ImageTransform`).

## Summary of Changes

1. **Split RenderHooks.swift** into 6 logical files across 3 layers
2. **Move FrameBuffer to Core** - it's renderer infrastructure, not an effect concern
3. **Move preroll logic to renderer** - UI shouldn't manage frame buffer population
4. **Rename `willRenderFrame` → `apply`** - cleaner, matches mental model
5. **Add renderer readiness API** (future) - unified signal for UI to observe

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 1: Renderer/Core/  (Pipeline + GPU Infrastructure)      │
│                                                                 │
│  SharedRenderer.swift     - Metal device, CIContext singleton   │
│  FrameBuffer.swift        - Temporal frame storage (internal)   │
│  RenderContext.swift      - Per-frame context (public)          │
│  CompositionBuilder.swift - Builds AVComposition (existing)     │
│  FrameProcessor.swift     - Per-frame processing (existing)     │
│  RenderEngine.swift       - Export engine (existing)            │
│  ... other existing core files                                  │
│                                                                 │
│  Core OWNS and POPULATES FrameBuffer.                           │
│  Core EXPORTS RenderContext (wraps frame access).               │
│  Pipeline accepts `[Effect]` at transform points.               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 2: Renderer/Effects/  (Effects System)                  │
│                                                                 │
│  Effect.swift             - Protocol + Params helper            │
│  ParameterSpec.swift      - Parameter metadata enum             │
│  ChainedEffect.swift      - Composes multiple effects           │
│  BasicEffect.swift        - Brightness/contrast/saturation      │
│  DatamoshEffect.swift     - Temporal glitch                     │
│  ... all individual effects                                     │
│                                                                 │
│  Pure transforms. No app-specific dependencies.                 │
│  Imports: RenderContext, SharedRenderer from Core               │
│  Does NOT import FrameBuffer (accessed via RenderContext)       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 3: EffectLibrary/  (App Integration)                    │
│                                                                 │
│  EffectManager.swift      - Manages active effects for app      │
│  EffectChainLibrary.swift - Static library of effect chains    │
│                                                                 │
│  Knows about: HypnogramRecipe, EffectDefinition, etc.           │
│  This is the glue between Effects and the app's data model.     │
└─────────────────────────────────────────────────────────────────┘
```

## Files to Create (from RenderHooks.swift)

| New File | Contents | Lines (approx) |
|----------|----------|----------------|
| `Renderer/Core/SharedRenderer.swift` | SharedRenderer enum | ~50 |
| `Renderer/Core/FrameBuffer.swift` | FrameBuffer class (internal to Core) | ~180 |
| `Renderer/Core/RenderContext.swift` | RenderContext struct (public, wraps frame access) | ~80 |
| `Renderer/Effects/Effect.swift` | Effect protocol + Params helper | ~100 |
| `Renderer/Effects/ParameterSpec.swift` | ParameterSpec enum + extensions | ~200 |
| `EffectLibrary/EffectManager.swift` | EffectManager class | ~450 |
| `EffectLibrary/EffectChainLibrary.swift` | EffectChainLibrary enum | ~100 |

## RenderContext Encapsulates Frame Access

Effects need previous frames for temporal effects. Instead of exposing FrameBuffer directly,
RenderContext provides frame access methods:

```swift
// RenderContext (in Core, public)
struct RenderContext {
    let frameIndex: Int
    let time: CMTime
    let outputSize: CGSize
    var sourceIndex: Int?

    // Frame access - hides FrameBuffer implementation
    func previousFrame(offset: Int) -> CIImage?
    var currentFrame: CIImage?
    var frameCount: Int

    // Internal: FrameBuffer reference (not exposed to Effects)
    internal let frameBuffer: FrameBuffer
}
```

**Before (Effects know about FrameBuffer):**
```swift
let prev = context.frameBuffer.previousFrame(offset: 5)
```

**After (Effects use RenderContext API):**
```swift
let prev = context.previousFrame(offset: 5)
```

**Benefits:**
- FrameBuffer is an implementation detail of Core
- Effects only depend on RenderContext (cleaner interface)
- Core can change FrameBuffer internals without affecting Effects

## Why FrameBuffer is Internal to Core

FrameBuffer is **renderer infrastructure**, not an effect concern:

1. **"Ready to play" is a renderer state** - The renderer signals when buffered
2. **Preroll is a renderer operation** - Core populates the buffer
3. **Effects are consumers** - They read frames via RenderContext, not FrameBuffer
4. **Encapsulation** - Effects don't need to know how frames are stored

**Current (leaky):**
```
UI → EffectManager → FrameBuffer → preroll
Effects → context.frameBuffer.previousFrame()
```

**After (encapsulated):**
```
UI → Renderer.prepare() → Core handles preroll internally
Effects → context.previousFrame()  (FrameBuffer hidden)
```

## Move Preroll Logic to Renderer

Currently, preroll is called from UI layer (SequencePlayerView):

```swift
// Current: UI reaches into effectManager to preroll
let frameBuffer = self.effectManager.frameBuffer
let count = await frameBuffer.preroll(from: asset, startTime: CMTime.zero)
// then start playback
```

This should move into the renderer. The renderer should:
1. Own the FrameBuffer
2. Handle preroll internally when preparing a composition
3. Signal when ready (see Future: Renderer Readiness API)

**Files with preroll/prefill calls to refactor:**
- `SequencePlayerView.swift` - calls `frameBuffer.preroll()` for video
- `SequencePlayerView.swift` - calls `frameBuffer.prefill()` for still images
- `MontagePlayerView.swift` - does NOT preroll (uses AVVideoComposition on-demand)

**Note:** MontagePlayerView uses AVVideoComposition which renders frames on-demand via
FrameCompositor. It may need preroll added for consistent temporal effect behavior,
or it may work differently. Evaluate during implementation.

## Future: Renderer Readiness API

After this refactor, we can add a unified readiness signal:

```swift
enum RenderReadiness {
    case notReady
    case preparingMedia       // building composition
    case bufferingFrames(progress: Float)  // preroll in progress
    case ready
}

// On RenderEngine or a new RenderSession type
@Published var readiness: RenderReadiness
```

**Benefits:**
- UI observes one signal instead of manually coordinating preroll + playerItem.status
- Enables proper player double-buffering (keep playing old until new is ready)
- Clean separation: renderer knows when it's ready, UI just reacts

**This is OUT OF SCOPE for initial refactor** but the architecture enables it.

## API Changes

### Rename `willRenderFrame` → `apply`
```swift
// Before
func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage

// After  
func apply(to image: CIImage, context: inout RenderContext) -> CIImage
```

Rationale: Cleaner, matches "apply an effect" mental model, image comes first.

## Execution Steps

### Phase 1: Create new files (no deletions yet)

- [ ] Create `Renderer/Core/SharedRenderer.swift`
- [ ] Create `Renderer/Core/FrameBuffer.swift` (internal to Core)
- [ ] Create `Renderer/Core/RenderContext.swift` (public, wraps frame access)
- [ ] Create `Renderer/Effects/Effect.swift` (protocol + Params helper)
- [ ] Create `Renderer/Effects/ParameterSpec.swift`
- [ ] Create `EffectLibrary/EffectManager.swift`
- [ ] Create `EffectLibrary/EffectChainLibrary.swift`

### Phase 2: Update Effect protocol and all effects

- [ ] Rename `willRenderFrame` → `apply` in protocol
- [ ] Update all 25+ effect files to use new signature
- [ ] Update callers in FrameProcessor, FrameCompositor, etc.

### Phase 3: Move preroll responsibility to renderer

- [ ] Move `frameBuffer.preroll()` call from SequencePlayerView into RenderEngine or CompositionBuilder
- [ ] Move `frameBuffer.prefill()` call from SequencePlayerView into renderer
- [ ] EffectManager no longer owns FrameBuffer; renderer does
- [ ] Update EffectManager to receive FrameBuffer reference (or access via RenderContext)

### Phase 4: Update imports and verify build

- [ ] Add imports to all files that use Effect, ParameterSpec, etc.
- [ ] Verify build succeeds
- [ ] Run tests

### Phase 5: Remove old code

- [ ] Delete contents from RenderHooks.swift (or delete file entirely)
- [ ] Final build verification

## Files That Will Need Import Updates

These files currently get types from RenderHooks.swift and will need explicit imports:

**Renderer/Core/**
- FrameProcessor.swift (uses RenderContext, Effect)
- CompositionBuilder.swift (uses EffectManager)
- RenderInstruction.swift (uses Effect, EffectManager)
- FrameBuffer.swift is internal - only used within Core

**Renderer/Effects/** (all effect files)
- Use Effect protocol, RenderContext, ParameterSpec, SharedRenderer
- Do NOT import FrameBuffer (access frames via RenderContext)

**EffectLibrary/**
- EffectConfigLoader.swift (uses Effect, ParameterSpec)
- EffectRegistry.swift (uses Effect)

**App layer**
- Various files that use EffectManager

## Rollback Plan

If something goes wrong:
- Git revert to commit before starting
- All changes are additive in Phase 1, destructive only in Phase 4

## Notes

- Keep `RenderHook` typealias temporarily for compatibility during migration
- SharedRenderer stays in Core - GPU infrastructure used by both pipeline and effects
- FrameBuffer is internal to Core - effects access frames via RenderContext
- RenderContext is the public interface for frame access
- Preroll/prefill are renderer responsibilities, not UI responsibilities
- The renderer readiness API is a future enhancement enabled by this architecture
