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
- Named container for 0-n EffectDefinitions
- Stored on recipes (global or per-source)
- JSON-serializable for library storage

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
- Provides `applyGlobal()` and `applyToSource()` methods
- Manages effect cycling, randomization, flash solo

### Data Flow

1. **Config Loading**: `effects.json` → `EffectChainLibrary.all` (cached EffectChain array)
2. **Recipe Creation**: User selects chain → `HypnogramRecipe.effectChain` + instantiated `effects: [Effect]`
3. **Rendering**: `FrameCompositor` reads `recipe.effects` and applies each effect in sequence

### Recipe Structure

```swift
HypnogramRecipe {
    sources: [HypnogramSource]  // Each source has its own effectChain + effects
    effects: [Effect]            // Global instantiated effects (post-blend)
    effectChain: EffectChain?    // Global chain definition (source of truth)
}

HypnogramSource {
    clip: VideoClip
    effects: [Effect]            // Per-source instantiated effects (pre-blend)
    effectChain: EffectChain?    // Per-source chain definition
    blendMode: String?
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

- **Preview**: Uses `HypnographState.effectManager` (shared, mutable)
- **Export**: Creates isolated `EffectManager.forExport(recipe:)` with `recipe.copyForExport()`
- This prevents stateful effects from sharing state between preview and export
