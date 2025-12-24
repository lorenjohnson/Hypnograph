//
//  RenderContext.swift
//  Hypnograph
//
//  Per-frame context passed to effects during rendering.
//  Provides frame access methods that hide FrameBuffer implementation.
//  Extracted from RenderHooks.swift as part of effects architecture refactor.
//

import CoreGraphics
import CoreMedia
import CoreImage
import Metal

/// Per-frame context, used by BOTH preview and export.
/// Effects access previous frames through this context's methods,
/// not by directly accessing FrameBuffer.
struct RenderContext {
    let frameIndex: Int
    let time: CMTime
    let outputSize: CGSize

    /// Index of the source currently being processed (if any).
    /// - `nil` when rendering the final composed frame or when no specific source is in scope.
    var sourceIndex: Int?

    /// Internal: Access to the frame buffer (not exposed to Effects layer)
    internal let frameBuffer: FrameBuffer

    init(
        frameIndex: Int,
        time: CMTime,
        outputSize: CGSize,
        frameBuffer: FrameBuffer,
        sourceIndex: Int? = nil
    ) {
        self.frameIndex = frameIndex
        self.time = time
        self.outputSize = outputSize
        self.frameBuffer = frameBuffer
        self.sourceIndex = sourceIndex
    }

    // MARK: - Frame Access (public API for Effects)

    /// Get previous frame as CIImage (offset: 1 = previous, 2 = two frames ago, etc.)
    /// In looping mode, wraps around if offset exceeds available frames.
    func previousFrame(offset: Int = 1) -> CIImage? {
        frameBuffer.previousFrame(offset: offset)
    }

    /// Get the most recently added frame
    var currentFrame: CIImage? {
        frameBuffer.currentFrame
    }

    /// Number of valid frames currently stored
    var frameCount: Int {
        frameBuffer.frameCount
    }

    /// Check if buffer has minimum frames for temporal effects
    var isBufferFilled: Bool {
        frameBuffer.isFilled
    }

    // MARK: - Metal Texture Access (for Metal compute shaders)

    /// Get previous frame as MTLTexture for Metal compute shaders
    /// - Parameter offset: History offset (1 = previous frame, 2 = two frames ago, etc.)
    /// - Returns: MTLTexture backed by the same IOSurface (zero-copy)
    func previousTexture(offset: Int = 1) -> MTLTexture? {
        frameBuffer.previousTexture(offset: offset)
    }

    /// Get texture at specific history offset (thread-safe)
    /// - Parameter offset: How far back in history (0 = most recent)
    func texture(atHistoryOffset offset: Int) -> MTLTexture? {
        frameBuffer.texture(atHistoryOffset: offset)
    }

    // MARK: - Convenience

    /// Convenience for creating a copy with a specific source index.
    func withSourceIndex(_ index: Int?) -> RenderContext {
        var copy = self
        copy.sourceIndex = index
        return copy
    }
}

