//
//  FrameCompositor.swift
//  Hypnograph
//
//  Stateless frame compositor - receives instructions, outputs frames
//  Minimal skeleton: single layer, no blending, no effects
//

import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import Metal

final class FrameCompositor: NSObject, AVVideoCompositing {

    // MARK: - Properties

    /// Use shared CIContext for GPU-efficient rendering (no duplicate Metal contexts)
    private var ciContext: CIContext { SharedRenderer.ciContext }

    private let renderQueue = DispatchQueue(label: "com.hypnograph.framecompositor", qos: .userInteractive)

    // Export manager - created lazily when first export frame is rendered
    // Uses same code path as preview, just with frozen recipe and isolated state
    private var exportManager: RenderHookManager?

    // MARK: - Initialization

    override init() {
        super.init()
        // Compositor initialized - logging removed for performance
    }

    // MARK: - AVVideoCompositing Protocol

    var sourcePixelBufferAttributes: [String : Any]? {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferOpenGLCompatibilityKey as String: true
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String : Any] {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferOpenGLCompatibilityKey as String: true
        ]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Nothing to do - we're stateless
    }

    // MARK: - Frame Rendering

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        // Per-frame logging removed for performance (30fps = 30 logs/sec)
        // NOTE: We capture self strongly here because AVFoundation owns the compositor
        // and can deallocate it at any time. If AVFoundation deallocates us while
        // we have pending work, that's an AVFoundation bug we can't fix with weak self.
        // Using weak self just causes the "self is nil" errors without fixing the root cause.
        renderQueue.async {
            self.renderFrame(request: request)
        }
    }
    
    func cancelAllPendingVideoCompositionRequests() {
        // Nothing to cancel - we process synchronously
    }
    
    // MARK: - Core Rendering
    
    private func renderFrame(request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? RenderInstruction else {
            print("🔴 FrameCompositor: Invalid instruction type")
            request.finish(with: NSError(domain: "FrameCompositor", code: 2, userInfo: nil))
            return
        }

        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            print("🔴 FrameCompositor: Failed to create output buffer")
            request.finish(with: NSError(domain: "FrameCompositor", code: 3, userInfo: nil))
            return
        }

        let outputSize = CGSize(
            width: CVPixelBufferGetWidth(outputBuffer),
            height: CVPixelBufferGetHeight(outputBuffer)
        )

        // Get the manager: preview uses global shared manager, export uses dedicated manager
        let isExport = instruction.recipeSnapshot != nil
        let manager: RenderHookManager?
        if isExport {
            // Create export manager on first frame (lazy, with frozen recipe)
            if exportManager == nil, let recipe = instruction.recipeSnapshot {
                exportManager = RenderHookManager.forExport(recipe: recipe)
            }
            manager = exportManager
        } else {
            manager = GlobalRenderHooks.manager
        }

        // Both paths now use the same manager interface
        let frameIndex = manager?.nextFrameIndex() ?? 0

        // Composite all layers
        var composited: CIImage?

        for (index, trackID) in instruction.layerTrackIDs.enumerated() {
            let sourceIndex = instruction.sourceIndices[index]

            // Check flash solo - skip layers that shouldn't be rendered (preview only)
            if let manager = manager, !manager.shouldRenderSource(at: sourceIndex) {
                continue
            }

            var layerImage: CIImage?

            // Check if this layer is a still image
            if index < instruction.stillImages.count, let stillImage = instruction.stillImages[index] {
                layerImage = stillImage
            } else {
                // Get frame from video track
                guard let sourceBuffer = request.sourceFrame(byTrackID: trackID) else {
                    print("⚠️ FrameCompositor: No source frame for track \(trackID) at \(request.compositionTime.seconds)s")
                    continue
                }
                layerImage = CIImage(cvPixelBuffer: sourceBuffer)
            }

            guard var img = layerImage else {
                continue
            }

            // Apply combined transform (metadata orientation + user transform)
            let transform = instruction.transforms[index]
            img = img.transformed(by: transform)

            // Aspect-fill to output size (handles origin normalization internally)
            img = ImageUtils.aspectFill(image: img, to: outputSize)

            // Apply per-source effects from recipe
            if instruction.enableEffects, let manager = manager {
                let recipe = manager.recipeProvider?()
                if let recipe = recipe, sourceIndex < recipe.sources.count {
                    let effects = recipe.sources[sourceIndex].effects
                    if !effects.isEmpty {
                        var sourceContext = RenderContext(
                            frameIndex: frameIndex,
                            time: request.compositionTime,
                            outputSize: outputSize,
                            frameBuffer: manager.frameBuffer
                        )
                        for effect in effects {
                            img = effect.willRenderFrame(&sourceContext, image: img)
                        }
                    }
                }
            }

            // Blend with previous layers
            if let base = composited {
                // Get blend mode from recipe
                let blendMode: String
                let recipe = manager?.recipeProvider?()

                if let recipe = recipe, sourceIndex < recipe.sources.count {
                    blendMode = sourceIndex == 0
                        ? BlendMode.sourceOver
                        : (recipe.sources[sourceIndex].blendMode ?? BlendMode.defaultMontage)
                } else {
                    blendMode = instruction.blendModes[index]
                }

                // Get compensated opacity from manager (same for preview and export)
                let opacity = manager?.compensatedOpacity(
                    layerIndex: index,
                    totalLayers: instruction.layerTrackIDs.count,
                    blendMode: blendMode
                ) ?? 1.0

                img = ImageUtils.blend(layer: img, over: base, mode: blendMode, opacity: opacity)
                composited = img
            } else {
                composited = img
            }
        }

        guard var finalImage = composited else {
            print("🔴 FrameCompositor: No layers composited")
            request.finish(with: NSError(domain: "FrameCompositor", code: 5, userInfo: nil))
            return
        }

        // Apply blend normalization (same for preview and export)
        if let manager = manager {
            finalImage = manager.applyNormalization(to: finalImage)
        }

        // Apply global effects from recipe
        if instruction.enableEffects, let manager = manager {
            let recipe = manager.recipeProvider?()
            if let recipe = recipe, !recipe.effects.isEmpty {
                var context = RenderContext(
                    frameIndex: frameIndex,
                    time: request.compositionTime,
                    outputSize: outputSize,
                    frameBuffer: manager.frameBuffer
                )
                for effect in recipe.effects {
                    finalImage = effect.willRenderFrame(&context, image: finalImage)
                }
            }
        }

        // Store frame in buffer
        if let manager = manager {
            manager.frameBuffer.addFrame(finalImage, at: request.compositionTime)
        }

        // Render to output buffer
        ciContext.render(finalImage, to: outputBuffer)

        // Finish request
        request.finish(withComposedVideoFrame: outputBuffer)
    }
}

