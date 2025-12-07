//
//  FrameProcessor.swift
//  Hypnograph
//
//  Unified frame processing pipeline for both preview and export.
//  Handles: CIImage input → aspect fill → effects → blending → output
//  Source-agnostic: works with video frames or still images.
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Input for a single layer in the processing pipeline
struct LayerInput {
    let image: CIImage
    let sourceIndex: Int
    let transform: CGAffineTransform
    let blendMode: String
    
    init(
        image: CIImage,
        sourceIndex: Int,
        transform: CGAffineTransform = .identity,
        blendMode: String = "CISourceOverCompositing"
    ) {
        self.image = image
        self.sourceIndex = sourceIndex
        self.transform = transform
        self.blendMode = blendMode
    }
}

/// Configuration for frame processing
struct ProcessingConfig {
    let outputSize: CGSize
    let time: CMTime
    let enableEffects: Bool

    init(
        outputSize: CGSize,
        time: CMTime = .zero,
        enableEffects: Bool = true
    ) {
        self.outputSize = outputSize
        self.time = time
        self.enableEffects = enableEffects
    }
}

/// Unified frame processor - handles all CIImage processing
/// Used by both preview (MTKView, AVPlayer) and export (AVAssetWriter)
final class FrameProcessor {

    /// Use shared CIContext for GPU efficiency (avoids duplicate Metal contexts)
    private var ciContext: CIContext { SharedRenderer.ciContext }

    init() {
        // No setup needed - uses shared context
    }
    
    // MARK: - Single Layer Processing
    
    /// Process a single source image (apply effects, aspect fill)
    func processSingleSource(
        _ image: CIImage,
        sourceIndex: Int,
        config: ProcessingConfig,
        manager: RenderHookManager? = nil
    ) -> CIImage {
        var img = image

        // Aspect-fill to output size
        img = ImageUtils.aspectFill(image: img, to: config.outputSize)
        
        // Apply per-source effects if enabled
        if config.enableEffects, let manager = manager {
            var context = RenderContext(
                frameIndex: 0,
                time: config.time,
                outputSize: config.outputSize,
                frameBuffer: manager.frameBuffer,
                sourceIndex: sourceIndex
            )
            img = manager.applyToSource(sourceIndex: sourceIndex, context: &context, image: img)
        }

        // Apply global effects
        if config.enableEffects, let manager = manager {
            var context = RenderContext(
                frameIndex: 0,
                time: config.time,
                outputSize: config.outputSize,
                frameBuffer: manager.frameBuffer
            )
            img = manager.applyGlobal(to: &context, image: img)
        }
        
        return img
    }
    
    // MARK: - Multi-Layer Compositing

    /// Composite multiple layers with blending and effects
    func compositeMultipleLayers(
        _ layers: [LayerInput],
        config: ProcessingConfig,
        manager: RenderHookManager? = nil
    ) -> CIImage? {
        guard !layers.isEmpty else { return nil }

        let totalLayers = layers.count
        var composited: CIImage?

        for (index, layer) in layers.enumerated() {
            // Check flash solo - skip layers that shouldn't be rendered
            if config.enableEffects,
               let manager = manager,
               !manager.shouldRenderSource(at: layer.sourceIndex) {
                continue
            }

            var img = layer.image

            // Apply transform
            if layer.transform != .identity {
                img = img.transformed(by: layer.transform)
            }

            // Aspect-fill to output size
            img = ImageUtils.aspectFill(image: img, to: config.outputSize)

            // Apply per-source effects
            if config.enableEffects, let manager = manager {
                var context = RenderContext(
                    frameIndex: 0,
                    time: config.time,
                    outputSize: config.outputSize,
                    frameBuffer: manager.frameBuffer,
                    sourceIndex: layer.sourceIndex
                )
                img = manager.applyToSource(sourceIndex: layer.sourceIndex, context: &context, image: img)
            }

            // Blend with previous layers
            if let base = composited {
                // Get blend mode and opacity from manager if available
                let blendMode: String
                let opacity: CGFloat

                if config.enableEffects, let manager = manager {
                    blendMode = manager.blendMode(for: layer.sourceIndex)
                    // Get compensated opacity from normalization strategy
                    opacity = manager.compensatedOpacity(
                        layerIndex: index,
                        totalLayers: totalLayers,
                        blendMode: blendMode
                    )
                } else {
                    blendMode = layer.blendMode
                    opacity = 1.0
                }
                img = ImageUtils.blend(layer: img, over: base, mode: blendMode, opacity: opacity)
            }

            composited = img
        }

        guard var finalImage = composited else { return nil }

        // Apply blend normalization (after compositing, before global effects)
        if config.enableEffects, let manager = manager {
            finalImage = manager.applyNormalization(to: finalImage)
        }

        // Apply global effects
        if config.enableEffects, let manager = manager {
            var context = RenderContext(
                frameIndex: 0,
                time: config.time,
                outputSize: config.outputSize,
                frameBuffer: manager.frameBuffer
            )
            finalImage = manager.applyGlobal(to: &context, image: finalImage)
        }

        return finalImage
    }

    // MARK: - Rendering to Output

    /// Render processed CIImage to a CVPixelBuffer
    func render(_ image: CIImage, to pixelBuffer: CVPixelBuffer) {
        ciContext.render(image, to: pixelBuffer)
    }

    /// Render processed CIImage to a CGImage (for display or export)
    func renderToCGImage(_ image: CIImage) -> CGImage? {
        ciContext.createCGImage(image, from: image.extent)
    }
}

