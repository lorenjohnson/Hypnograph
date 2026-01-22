---
last_reviewed: 2026-01-18T00:00:00Z
---

# Rendering System Architecture

## Scope
This document describes the preview, performance display, and export rendering pipeline.

## Sources
- `HypnoCore/Renderer/Core/RenderEngine.swift`
- `HypnoCore/Renderer/Core/CompositionBuilder.swift` (internal)
- `HypnoCore/Renderer/Core/RenderInstruction.swift` (internal)
- `HypnoCore/Renderer/Core/FrameCompositor.swift` (internal)
- `HypnoCore/Renderer/Core/FrameBuffer.swift`
- `HypnoCore/Renderer/Core/RenderContext.swift`
- `HypnoCore/Renderer/Core/FrameBufferPreloader.swift`
- `HypnoCore/Renderer/Core/PhotoMontage.swift` (internal)
- `HypnoCore/Renderer/Core/RendererImageUtils.swift` (internal)
- `HypnoCore/Renderer/Core/SharedRenderer.swift`
- `HypnoCore/Renderer/FrameSource/FrameSource.swift`
- `HypnoCore/Renderer/FrameSource/AVPlayerFrameSource.swift`
- `HypnoCore/Renderer/Display/PlayerView.swift`
- `HypnoCore/Renderer/Transitions/TransitionRenderer.swift`
- `Hypnograph/Dream/PreviewPlayerView.swift`
- `Hypnograph/Dream/LivePlayer.swift`

## Core Components

### Public API (HypnoCore)
- `RenderEngine` is the primary entry point for preview and export.
- `RenderEngine.ExportQueue` handles async export jobs and progress callbacks.
- Models: `AspectRatio`, `RenderError`, and `renderSize(...)` are public sizing/error helpers.

### RenderEngine
- Entry point for preview and export.
- `makePlayerItem()` builds an `AVPlayerItem` for montage preview.
- `export()` builds a composition and runs `AVAssetExportSession` or a still-image montage.
- `RenderEngine.Config.enableGlobalEffects` gates effect usage across the pipeline.

### CompositionBuilder
- Builds `AVMutableComposition`, `AVMutableVideoComposition`, audio mix, and `RenderInstruction` objects.
- Builds montage compositions: layered tracks, looping per-source clips to `targetDuration`.

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

### RenderEngine.ExportQueue

- Wraps `RenderEngine.export()` to produce `.mov` files.
- Tracks active export jobs and posts status messages on completion.
- Calls `HypnoCoreHooks.onVideoExportCompleted` on success for external destinations.

### PhotoMontage (still-image export)
- When montage output has no actual video segments, export uses `PhotoMontage` to
  produce a PNG instead of a movie file.

## Data Flow

### Preview
1. Dream or LivePlayer constructs a `HypnogramRecipe`.
2. `RenderEngine.makePlayerItem()` builds an `AVPlayerItem` and configures the internal compositor.
3. `FrameCompositor` renders frames using the `EffectManager` passed through internal instructions.
4. `PreviewPlayerView` displays the result via `AVPlayerFrameSource` → `PlayerView` (`MTKView`), enabling shader transitions.

### Live Display (LivePlayer)
- LivePlayer owns its own `EffectManager` and `EffectsSession`.
- It builds `AVPlayerItem` objects via `RenderEngine` and displays them through the Metal playback pipeline:
  `AVPlayerFrameSource` (pull frames via `AVPlayerItemVideoOutput`) → `PlayerView` (`MTKView`) with shader transitions.
- Live in-app previews mirror the same A/B state using `PlayerContentMirrorView`.

### Export
1. `RenderEngine.ExportQueue` calls `RenderEngine.export()`.
2. The recipe is copied via `recipe.copyForExport()` and rendered with
   `EffectManager.forExport()` for isolated state.
3. If montage output contains only still images, `PhotoMontage` exports a PNG.
4. Otherwise `AVAssetExportSession` writes a `.mov`.

## Montage Details

- Each source gets its own video track.
- Video clips loop to fill `targetDuration`.
- Still images create empty time ranges and are passed as `stillImages` in
  internal render instructions.
- Multiple audio tracks are mixed with normalized volume to reduce clipping.

## Output Sizing
- Render sizes are computed via `renderSize(aspectRatio:maxDimension)` using
  `AspectRatio` and `OutputResolution`.
- Preview sizing uses the active player's `PlayerConfiguration`.

## Slow Motion
- When `playRate < 1.0`, `FrameCompositor` uses a slow-motion pipeline on macOS 15.4+.
- Falls back to a crossfade interpolator when needed.

## Known Gaps and Risks
- No frame dropping or throttling under load; AVFoundation will back-pressure when rendering exceeds frame time.
- The renderer maintains two pipelines (AVFoundation compositor for video and an app-level CI/Metal path for still images). This adds complexity but keeps still-image rendering responsive and effect-capable alongside video playback.
- `FrameProcessor` (app-level) largely duplicates `FrameCompositor` logic and is only used for still-image display paths.
- `FrameBuffer` can be large at full capacity (up to 120 frames); there is no memory pressure handling.
- Some operations (blend normalization, recipe access) run per frame and rely on caching for performance.

## Notes and Constraints
- Rendering uses a shared `CIContext` from `SharedRenderer` for GPU efficiency.
- `FrameCompositor` runs on a `.userInitiated` queue to avoid starving audio.
- `FrameProcessor` is a secondary app-level CIImage pipeline used for non-AVFoundation paths
  (e.g., still image rendering); the core path is `FrameCompositor`.

## Backend Seams (Planned Flexibility)

- The `FrameSource` protocol is the main extensibility point for **frame providers** (e.g., AVPlayer-based vs. AVAssetReader-based).
- The **display backend** is not fully abstracted today:
  - `PlayerView` is Metal/`MTKView`-based.
  - Playback orchestration (`PlayerContentView`) is AVFoundation/`AVPlayerItem`-based.
  - Supporting multiple end-to-end backends would require a higher-level backend interface above these types.
