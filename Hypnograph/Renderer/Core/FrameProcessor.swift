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
    let isPreview: Bool
    let enableEffects: Bool
    
    init(
        outputSize: CGSize,
        time: CMTime = .zero,
        isPreview: Bool = true,
        enableEffects: Bool = true
    ) {
        self.outputSize = outputSize
        self.time = time
        self.isPreview = isPreview
        self.enableEffects = enableEffects
    }
}

/// Unified frame processor - handles all CIImage processing
/// Used by both preview (MTKView, AVPlayer) and export (AVAssetWriter)
final class FrameProcessor {
    
    private let ciContext: CIContext
    
    init(ciContext: CIContext? = nil) {
        self.ciContext = ciContext ?? CIContext(options: [
            .useSoftwareRenderer: false,
            .priorityRequestLow: false
        ])
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
        img = aspectFill(image: img, to: config.outputSize)
        
        // Apply per-source effects if enabled
        if config.enableEffects, let manager = manager {
            var context = RenderContext(
                frameIndex: 0,
                time: config.time,
                isPreview: config.isPreview,
                outputSize: config.outputSize,
                frameBuffer: manager.frameBuffer,
                params: RenderParams(),
                sourceIndex: sourceIndex
            )
            img = manager.applyToSource(sourceIndex: sourceIndex, context: &context, image: img)
        }
        
        // Apply global effects
        if config.enableEffects, let manager = manager {
            var context = RenderContext(
                frameIndex: 0,
                time: config.time,
                isPreview: config.isPreview,
                outputSize: config.outputSize,
                frameBuffer: manager.frameBuffer,
                params: RenderParams()
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
        
        var composited: CIImage?
        
        for layer in layers {
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
            img = aspectFill(image: img, to: config.outputSize)
            
            // Apply per-source effects
            if config.enableEffects, let manager = manager {
                var context = RenderContext(
                    frameIndex: 0,
                    time: config.time,
                    isPreview: config.isPreview,
                    outputSize: config.outputSize,
                    frameBuffer: manager.frameBuffer,
                    params: RenderParams(),
                    sourceIndex: layer.sourceIndex
                )
                img = manager.applyToSource(sourceIndex: layer.sourceIndex, context: &context, image: img)
            }
            
            // Blend with previous layers
            if let base = composited {
                // Get blend mode from manager if available (for dynamic changes)
                let blendMode: String
                if config.enableEffects, let manager = manager {
                    blendMode = manager.blendMode(for: layer.sourceIndex)
                } else {
                    blendMode = layer.blendMode
                }
                img = blend(layer: img, over: base, mode: blendMode)
            }
            
            composited = img
        }
        
        guard var finalImage = composited else { return nil }
        
        // Apply global effects
        if config.enableEffects, let manager = manager {
            var context = RenderContext(
                frameIndex: 0,
                time: config.time,
                isPreview: config.isPreview,
                outputSize: config.outputSize,
                frameBuffer: manager.frameBuffer,
                params: RenderParams()
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

    // MARK: - Helpers

    private func aspectFill(image: CIImage, to size: CGSize) -> CIImage {
        // First, translate image so its origin is at (0,0) if needed
        var img = image
        if img.extent.origin != .zero {
            img = img.transformed(by: CGAffineTransform(
                translationX: -img.extent.origin.x,
                y: -img.extent.origin.y
            ))
        }

        let imageSize = img.extent.size
        guard imageSize.width > 0, imageSize.height > 0, size.width > 0, size.height > 0 else {
            return img
        }

        let scale = max(size.width / imageSize.width, size.height / imageSize.height)

        let scaledImage = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledSize = scaledImage.extent.size

        let x = (size.width - scaledSize.width) / 2
        let y = (size.height - scaledSize.height) / 2

        let translated = scaledImage.transformed(by: CGAffineTransform(translationX: x, y: y))

        return translated.cropped(to: CGRect(origin: .zero, size: size))
    }

    private func blend(layer: CIImage, over base: CIImage, mode: String) -> CIImage {
        let filter = CIFilter(name: mode)
        filter?.setValue(layer, forKey: kCIInputImageKey)
        filter?.setValue(base, forKey: kCIInputBackgroundImageKey)
        return filter?.outputImage ?? layer
    }
}

