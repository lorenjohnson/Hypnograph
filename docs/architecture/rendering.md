---
last_reviewed: 2026-01-03T21:17:01Z
---

# Rendering System Architecture

## Scope
This document describes the preview, performance display, and export rendering pipeline.

## Sources
- `Hypnograph/Renderer/Core/RenderEngine.swift`
- `Hypnograph/Renderer/Core/CompositionBuilder.swift`
- `Hypnograph/Renderer/Core/RenderInstruction.swift`
- `Hypnograph/Renderer/Core/FrameCompositor.swift`
- `Hypnograph/Renderer/Core/FrameBuffer.swift`
- `Hypnograph/Renderer/Core/RenderContext.swift`
- `Hypnograph/Renderer/Core/FrameBufferPreloader.swift`
- `Hypnograph/Renderer/Core/RenderQueue.swift`
- `Hypnograph/Renderer/Core/HypnogramRenderer.swift`
- `Hypnograph/Renderer/Core/PhotoMontage.swift`
- `Hypnograph/Renderer/Core/RenderSize.swift`
- `Hypnograph/Renderer/Core/SharedRenderer.swift`
- `Hypnograph/Modules/PerformanceDisplay/LivePlayer.swift`

## Core Components

### RenderEngine
- Entry point for preview and export.
- `makePlayerItem()` builds an `AVPlayerItem` for montage or sequence preview.
- `export()` builds a composition and runs `AVAssetExportSession` or a still-image montage.
- `RenderEngine.Config.enableGlobalEffects` and `CompositionBuilder.enableEffects` gate effect usage.

### CompositionBuilder
- Builds `AVMutableComposition`, `AVMutableVideoComposition`, audio mix, and `RenderInstruction` objects.
- Supports two timeline strategies:
  - Montage: layered tracks, looping per-source clips to `targetDuration`.
  - Sequence: single track, clips concatenated end-to-end.

### RenderInstruction
- Per-time-range instruction for `AVVideoCompositing`.
- Stores track IDs, blend modes, transforms, source indices, and still images.
- Carries a weak `EffectManager` so the compositor can apply per-source and global effects.

### FrameCompositor
- Custom `AVVideoCompositing` implementation used by preview and export.
- Steps per frame:
  1. Resolve video frame or still image for each layer.
  2. Apply metadata + user transforms, then aspect-fill.
  3. Apply per-source effects (if enabled).
  4. Blend layers using recipe blend modes and normalized opacity.
  5. Apply global effects, then store into `FrameBuffer`.
  6. Render the final `CIImage` into a `CVPixelBuffer` using `SharedRenderer.ciContext`.
- Handles slow-motion interpolation when `playRate < 1.0`.

### FrameBuffer and RenderContext
- `FrameBuffer` is a ring buffer of IOSurface-backed pixel buffers for temporal effects.
- `RenderContext` is the public API used by effects to access previous frames and textures.
- `FrameBufferPreloader` fills the buffer when temporal effects are active and
  `RendererConfig.prerollEnabled` is true.

### RenderQueue and HypnogramRenderer
- `HypnogramRenderer` wraps `RenderEngine.export()` to produce `.mov` files.
- `RenderQueue` tracks active export jobs and posts notifications on completion.

### PhotoMontage (still-image export)
- When montage output has no actual video segments, export uses `PhotoMontage` to
  produce a PNG instead of a movie file.

## Data Flow

### Preview
1. Dream or LivePlayer constructs a `HypnogramRecipe`.
2. `RenderEngine.makePlayerItem()` calls `CompositionBuilder.build()`.
3. `CompositionBuilder` produces an `AVMutableComposition` and `RenderInstruction` list.
4. `AVPlayerItem` + `AVMutableVideoComposition` are created, with
   `FrameCompositor` as the compositor.
5. `FrameCompositor` renders frames using the `EffectManager` passed through the
   `RenderInstruction`.

### Performance Display (LivePlayer)
- LivePlayer owns its own `EffectManager` and `EffectsSession`.
- It builds `AVPlayerItem` objects via `RenderEngine` and crossfades between two
  internal players (A/B) for smooth transitions.

### Export
1. `HypnogramRenderer` calls `RenderEngine.export()`.
2. The recipe is copied via `recipe.copyForExport()` and rendered with
   `EffectManager.forExport()` for isolated state.
3. If montage output contains only still images, `PhotoMontage` exports a PNG.
4. Otherwise `AVAssetExportSession` writes a `.mov`.

## Montage vs Sequence Details

### Montage
- Each source gets its own video track.
- Video clips loop to fill `targetDuration`.
- Still images create empty time ranges and are passed as `stillImages` in
  `RenderInstruction`.
- Multiple audio tracks are mixed with normalized volume to reduce clipping.

### Sequence
- Single video track and single audio track.
- Each clip is inserted sequentially with its own `RenderInstruction`.
- Still images are represented as empty time ranges with `stillImages` provided.

## Output Sizing
- Render sizes are computed via `renderSize(aspectRatio:maxDimension)` using
  `AspectRatio` and `OutputResolution`.
- Preview sizing uses the active player's `PlayerConfiguration`.

## Slow Motion
- When `playRate < 1.0`, `FrameCompositor` uses a slow-motion pipeline on macOS 15.4+.
- Falls back to a crossfade interpolator when needed.

## Known Gaps and Risks
- No frame dropping or throttling under load; AVFoundation will back-pressure when rendering exceeds frame time.
- `FrameProcessor` largely duplicates `FrameCompositor` logic and is only used for still-image display paths.
- `FrameBuffer` can be large at full capacity (up to 120 frames); there is no memory pressure handling.
- Some operations (blend normalization, recipe access) run per frame and rely on caching for performance.

## Notes and Constraints
- Rendering uses a shared `CIContext` from `SharedRenderer` for GPU efficiency.
- `FrameCompositor` runs on a `.userInitiated` queue to avoid starving audio.
- `FrameProcessor` is a secondary CIImage pipeline used for non-AVFoundation paths
  (e.g., still image rendering); the core path is `FrameCompositor`.
