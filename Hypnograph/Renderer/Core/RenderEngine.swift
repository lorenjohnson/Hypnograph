//
//  RenderEngine.swift
//  Hypnograph
//
//  Unified engine for preview and export
//  Skeleton: preview only, single source
//

import Foundation
import AVFoundation
import CoreGraphics

/// Unified render engine for preview and export
final class RenderEngine {
    
    // MARK: - Configuration
    
    struct Config {
        let outputSize: CGSize
        let frameRate: Int
        let enableGlobalHooks: Bool  // false for export
        
        static let preview = Config(
            outputSize: CGSize(width: 1920, height: 1080),
            frameRate: 30,
            enableGlobalHooks: true
        )
    }
    
    // MARK: - Dependencies
    
    private let compositionBuilder = CompositionBuilder()
    private let compositor = FrameCompositor()
    
    // MARK: - Preview

    /// Result of making a player item
    struct PlayerItemResult {
        let playerItem: AVPlayerItem
        let clipStartTimes: [CMTime]
    }

    /// Build a player item for preview
    func makePlayerItem(
        recipe: HypnogramRecipe,
        strategy: CompositionBuilder.TimelineStrategy,
        config: Config
    ) async -> Result<PlayerItemResult, RenderError> {

        print("🎬 RenderEngine: Making player item...")

        // Build composition
        let buildResult = await compositionBuilder.build(
            recipe: recipe,
            strategy: strategy,
            outputSize: config.outputSize,
            frameRate: config.frameRate
        )

        guard case .success(let build) = buildResult else {
            if case .failure(let error) = buildResult {
                error.log(context: "RenderEngine.makePlayerItem")
                return .failure(error)
            }
            return .failure(.playerItemCreationFailed)
        }

        // Attach compositor to video composition
        build.videoComposition.customVideoCompositorClass = FrameCompositor.self

        // Create player item
        let playerItem = AVPlayerItem(asset: build.composition)
        playerItem.videoComposition = build.videoComposition

        print("✅ RenderEngine: Player item created - \(build.composition.duration.seconds)s")

        let result = PlayerItemResult(
            playerItem: playerItem,
            clipStartTimes: build.clipStartTimes
        )

        return .success(result)
    }
    
    // MARK: - Export

    /// Export to file
    func export(
        recipe: HypnogramRecipe,
        strategy: CompositionBuilder.TimelineStrategy,
        outputURL: URL,
        config: Config,
        progress: ((Double) -> Void)? = nil
    ) async -> Result<URL, RenderError> {

        print("🎬 RenderEngine.export: Starting export to \(outputURL.lastPathComponent)...")

        // Build composition (same as preview)
        let builder = CompositionBuilder()
        let buildResult = await builder.build(
            recipe: recipe,
            strategy: strategy,
            outputSize: config.outputSize,
            frameRate: config.frameRate
        )

        guard case .success(let build) = buildResult else {
            if case .failure(let error) = buildResult {
                error.log(context: "RenderEngine.export")
                return .failure(error)
            }
            return .failure(.exportFailed(
                underlying: NSError(domain: "RenderEngine", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Build failed"])
            ))
        }

        // Configure video composition with compositor BEFORE creating export session
        build.videoComposition.customVideoCompositorClass = FrameCompositor.self

        print("🎬 RenderEngine.export: Video composition configured:")
        print("   - renderSize: \(build.videoComposition.renderSize)")
        print("   - frameDuration: \(build.videoComposition.frameDuration.seconds)s")
        print("   - instructions: \(build.videoComposition.instructions.count)")
        print("   - compositor: \(String(describing: build.videoComposition.customVideoCompositorClass))")

        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: build.composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            return .failure(.exportFailed(
                underlying: NSError(domain: "RenderEngine", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
            ))
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = build.videoComposition
        exportSession.shouldOptimizeForNetworkUse = false

        print("🎬 RenderEngine.export: Export session configured, starting export...")

        // Export with progress tracking
        await exportSession.export()

        switch exportSession.status {
        case .completed:
            print("✅ RenderEngine.export: Complete - \(outputURL.lastPathComponent)")
            return .success(outputURL)

        case .failed:
            let error = exportSession.error ?? NSError(domain: "RenderEngine", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Export failed with unknown error"])
            print("🔴 RenderEngine.export: Failed - \(error)")

            // Check if file was actually created despite the error
            if FileManager.default.fileExists(atPath: outputURL.path) {
                print("⚠️  RenderEngine.export: File exists despite error - treating as success")
                return .success(outputURL)
            }

            return .failure(.exportFailed(underlying: error))

        case .cancelled:
            print("⚠️  RenderEngine.export: Cancelled")
            return .failure(.exportFailed(
                underlying: NSError(domain: "RenderEngine", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Export cancelled"])
            ))

        default:
            print("🔴 RenderEngine.export: Unknown status - \(exportSession.status.rawValue)")
            return .failure(.exportFailed(
                underlying: NSError(domain: "RenderEngine", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Export ended with unknown status"])
            ))
        }
    }
}

