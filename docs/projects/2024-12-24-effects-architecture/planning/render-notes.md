# Render System & Effects Architecture

## Overview

The render system composes multiple video/image sources with effects into a final rendered output.
Effects are visual transformations applied either globally (post-composition) or per-source (pre-composition).

## Core Components

### Render Pipeline

```
HypnogramRecipe → CompositionBuilder → AVComposition + RenderInstruction
                                              ↓
                               AVPlayer → FrameCompositor → Final Frame
```

1. **RenderEngine** - Entry point for building compositions for preview or export
2. **CompositionBuilder** - Creates AVComposition with video/audio tracks and RenderInstructions
3. **RenderInstruction** - Per-instruction data: layer transforms, blend modes, source indices, effect manager reference
4. **FrameCompositor** - AVVideoCompositing implementation that renders each frame:
   - Extracts source frames from each layer
   - Applies per-source effects (before blending)
   - Blends layers with opacity compensation
   - Applies global effects (after blending)
5. **FrameProcessor** - Alternative frame processing path for non-AVFoundation contexts

### Effect System

**Effect Protocol** (`Effect.swift`):
- `name: String` - Display name
- `requiredLookback: Int` - Frames needed in buffer (0 = pure per-frame, 40+ = temporal effects)
- `static var parameterSpecs: [String: ParameterSpec]` - Parameter metadata (types, ranges, defaults)
- `init?(params: [String: AnyCodableValue]?)` - Create from params dictionary
- `apply(to: CIImage, context: inout RenderContext) -> CIImage` - Apply transformation
- `reset()` - Clear internal state
- `copy() -> Effect` - Clone for isolated rendering

**EffectChain** (`EffectConfigSchema.swift`):
- `final class` container for 0-n EffectDefinitions
- Stored on recipes (global `effectChain` or per-source `effectChain`)
- **Owns instantiated effects**: caches `[Effect]` lazily via `instantiatedEffects` property
- **Single source of truth**: definitions drive instantiation, no separate `effects: [Effect]` array
- JSON-serializable for library storage
- `copy() -> EffectChain` creates deep copy with fresh effect instances

**EffectDefinition** (`EffectConfigSchema.swift`):
- Single effect specification: type name + parameters
- Supports `_enabled` param for toggling within chain

**EffectChainLibrary** (`EffectChainLibrary.swift`):
- Static cache of all available effect chains
- Loads from: user config → bundled defaults → hardcoded fallback
- Provides `random()`, `forName(_:)`, `reload()` methods

**EffectRegistry** (`EffectRegistry.swift`):
- Maps type names to Effect.Type metatypes
- Creates Effect instances from type + params
- Provides parameter specs and defaults for each effect type

**EffectManager** (`EffectManager.swift`):
- Runtime manager for effects during rendering
- Holds frame buffer for temporal effects
- **Recipe-connected via closures**:
  - `recipeProvider: () -> HypnogramRecipe?` - reads recipe
  - `globalEffectChainSetter: (EffectChain) -> Void` - writes global chain
  - `sourceEffectChainSetter: (Int, EffectChain) -> Void` - writes per-source chain
- **Key methods**:
  - `setGlobalEffect(from: EffectChain)` / `setSourceEffect(from:for:)` - set effect (copies chain)
  - `clearEffect(for layer: Int)` - clear effect (-1 = global, 0+ = source index)
  - `applyGlobal(to:image:)` / `applyToSource(sourceIndex:to:image:)` - apply effects during render
- Manages effect cycling, randomization, flash solo

### Data Flow

1. **Config Loading**: `effects.json` → `EffectChainLibrary.all` (cached EffectChain array)
2. **Effect Selection**: User selects chain → `effectManager.setGlobalEffect(from: chain)` → copies chain to `recipe.effectChain`
3. **Rendering**: `EffectManager.applyGlobal()` calls `recipe.effectChain.apply(to:context:)` which uses cached instantiated effects
4. **Effect Persistence**: When creating new hypnogram, `resetForNextHypnogram(preserveGlobalEffect: true)` saves and restores `recipe.effectChain.copy()`

### Recipe Structure

```swift
HypnogramRecipe {
    sources: [HypnogramSource]  // Each source has its own effectChain
    effectChain: EffectChain    // Global chain (owns instantiated effects)
}

HypnogramSource {
    clip: VideoClip
    effectChain: EffectChain    // Per-source chain (owns instantiated effects)
    blendMode: BlendMode
}
```

### JSON Format (effects.json)

```json
{
  "version": 1,
  "effects": [
    {
      "name": "Datamosh: Subtle",
      "effects": [
        {
          "type": "DatamoshMetalEffect",
          "params": { "feedbackAmount": 0.73, ... }
        }
      ]
    }
  ]
}
```

### Key Effect Types

| Effect | Type | Description |
|--------|------|-------------|
| DatamoshMetalEffect | Temporal | GPU datamoshing with block propagation |
| GhostBlurEffect | Temporal | Motion trails with blur |
| HoldFrameEffect | Temporal | Periodic frame freezing |
| RGBSplitSimpleEffect | Visual | Chromatic aberration |
| PixelateMetalEffect | Visual | Block pixelation |
| BasicEffect | Color | Brightness, contrast, saturation |
| TextOverlayEffect | Overlay | Dynamic text rendering |

### Preview vs Export

- **Preview**: Uses `DreamPlayerState.effectManager` (player-specific, shared during session)
- **Export**: Creates isolated `EffectManager.forExport(recipe:)` with `recipe.copyForExport()`
- This prevents stateful effects from sharing state between preview and export

### Effect Chain Ownership

EffectChains are **copied** when assigned to recipes to ensure:
- Library chains remain immutable templates
- Parameter edits on active effects don't pollute library
- Each hypnogram gets its own independent effect state
- New hypnograms can preserve the previous effect selection

### Layer Selection

- `DreamPlayerState.currentSourceIndex` defaults to **-1 (global layer)**
- This ensures pressing "E" to cycle effects sets the **global** effect
- Global effects persist across new hypnograms via `resetForNextHypnogram(preserveGlobalEffect: true)`
- Press "0" to explicitly select global layer, "1-9" for source layers

### Frame Buffer Preloading

Temporal effects (Datamosh, GhostBlur, HoldFrame) require a filled frame buffer before they work correctly.

**Components:**
- `FrameBuffer` - Ring buffer storing recent frames (120 frames = ~4 seconds at 30fps)
- `FrameBufferPreloader` - Utility for prerolling frames from video/image sources
- `RendererConfig.prerollEnabled` - Global constant to enable/disable preroll

**Flow:**
1. When a source loads, `EffectManager.preloadFrameBuffer(from:)` is called
2. If `RendererConfig.prerollEnabled` is false, skip preroll entirely
3. If `usesFrameBuffer` is false (no temporal effects), skip preroll
4. Otherwise, `FrameBufferPreloader` extracts frames BEFORE playback start time
5. Playback begins with buffer already filled - effects work immediately

**Smart Preroll:**
- Effects advertise their lookback needs via `requiredLookback: Int`
- `EffectManager.maxRequiredLookback` finds the max across all active effects
- Only that many frames are prerolled (not the full 120-frame buffer)
- Effects with `requiredLookback = 0` (BasicEffect, TextOverlay, etc.) don't trigger preroll

**Trade-off:**
- Preroll extracts frames from the video before the start point
- For a 30-frame lookback at 30fps, this is effectively 1 second of "history"
- Most users won't notice, but clips may start slightly into the content
- Set `RendererConfig.prerollEnabled = false` to always start at beginning (effects build up naturally)
