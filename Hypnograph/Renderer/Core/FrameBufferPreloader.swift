//
//  FrameBufferPreloader.swift
//  Hypnograph
//
//  Handles prerolling/prefilling the frame buffer before playback.
//  Decouples frame buffer initialization from player views.
//

import Foundation
import AVFoundation
import CoreImage

/// Preloads frame buffer for temporal effects before playback starts
final class FrameBufferPreloader {
    
    /// Preload result
    enum PreloadResult {
        case success(frameCount: Int)
        case skipped(reason: String)
        case failed(reason: String)
    }
    
    /// Preload the frame buffer for a video asset
    /// - Parameters:
    ///   - asset: The video asset to preload frames from
    ///   - frameBuffer: The frame buffer to fill
    ///   - effectManager: Effect manager to check if preload is needed
    ///   - readiness: Optional readiness observer for progress updates
    ///   - startTime: Start time for preroll (default: .zero)
    /// - Returns: Result of the preload operation
    @MainActor
    static func preload(
        asset: AVAsset,
        frameBuffer: FrameBuffer,
        effectManager: EffectManager,
        readiness: RendererReadiness? = nil,
        startTime: CMTime = .zero
    ) async -> PreloadResult {
        // Check if preload is needed
        guard effectManager.usesFrameBuffer else {
            print("⏭️ FrameBufferPreloader: No temporal effects, skipping preroll")
            readiness?.setReady()
            return .skipped(reason: "No temporal effects")
        }
        
        let requiredFrames = min(effectManager.maxRequiredLookback, frameBuffer.maxFrames)
        guard requiredFrames > 0 else {
            print("⏭️ FrameBufferPreloader: Zero lookback required, skipping preroll")
            readiness?.setReady()
            return .skipped(reason: "Zero lookback required")
        }
        
        print("🎬 FrameBufferPreloader: Starting preroll, need \(requiredFrames) frames...")
        readiness?.setPrefilling(progress: 0.0)
        
        // Perform preroll
        let count = await frameBuffer.preroll(
            from: asset,
            startTime: startTime,
            frameCount: requiredFrames
        )
        
        if count > 0 {
            print("✅ FrameBufferPreloader: Preroll complete, \(count) frames loaded")
            readiness?.setReady()
            return .success(frameCount: count)
        } else {
            print("⚠️ FrameBufferPreloader: Preroll failed, no frames loaded")
            readiness?.setFailed(reason: "No frames loaded")
            return .failed(reason: "No frames loaded from asset")
        }
    }
    
    /// Preload the frame buffer for a still image
    /// - Parameters:
    ///   - image: The still image to prefill with
    ///   - frameBuffer: The frame buffer to fill
    ///   - effectManager: Effect manager to check if preload is needed
    ///   - readiness: Optional readiness observer for progress updates
    /// - Returns: Result of the preload operation
    @MainActor
    static func preload(
        image: CIImage,
        frameBuffer: FrameBuffer,
        effectManager: EffectManager,
        readiness: RendererReadiness? = nil
    ) -> PreloadResult {
        // Check if preload is needed
        guard effectManager.usesFrameBuffer else {
            print("⏭️ FrameBufferPreloader: No temporal effects, skipping prefill")
            readiness?.setReady()
            return .skipped(reason: "No temporal effects")
        }
        
        let requiredFrames = min(effectManager.maxRequiredLookback, frameBuffer.maxFrames)
        guard requiredFrames > 0 else {
            print("⏭️ FrameBufferPreloader: Zero lookback required, skipping prefill")
            readiness?.setReady()
            return .skipped(reason: "Zero lookback required")
        }
        
        print("🖼️ FrameBufferPreloader: Prefilling \(requiredFrames) frames for still image...")
        
        // Still image prefill is synchronous and fast
        let count = frameBuffer.prefill(with: image, frameCount: requiredFrames)
        
        if count > 0 {
            print("✅ FrameBufferPreloader: Prefill complete, \(count) frames loaded")
            readiness?.setReady()
            return .success(frameCount: count)
        } else {
            print("⚠️ FrameBufferPreloader: Prefill failed")
            readiness?.setFailed(reason: "Prefill failed")
            return .failed(reason: "Prefill returned 0 frames")
        }
    }
}

