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
import CoreImage

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
        /// Still images for each source index (for sequence mode override when seeking to still images)
        let stillImagesBySourceIndex: [Int: CIImage]
    }

    /// Build a player item for preview or isolated playback
    /// - Parameters:
    ///   - recipe: The recipe to build
    ///   - strategy: Montage or sequence timeline
    ///   - config: Render configuration
    ///   - hookManager: The RenderHookManager to use. If nil, uses global hooks.
    func makePlayerItem(
        recipe: HypnogramRecipe,
        strategy: CompositionBuilder.TimelineStrategy,
        config: Config,
        hookManager: RenderHookManager? = nil
    ) async -> Result<PlayerItemResult, RenderError> {

        // Build composition
        let buildResult = await compositionBuilder.build(
            recipe: recipe,
            strategy: strategy,
            outputSize: config.outputSize,
            frameRate: config.frameRate,
            hookManager: hookManager
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

        // Extract still images by source index from instructions (for sequence mode)
        var stillImagesBySourceIndex: [Int: CIImage] = [:]
        for instruction in build.instructions {
            for (layerIndex, sourceIndex) in instruction.sourceIndices.enumerated() {
                if layerIndex < instruction.stillImages.count,
                   let stillImage = instruction.stillImages[layerIndex] {
                    stillImagesBySourceIndex[sourceIndex] = stillImage
                }
            }
        }

        let result = PlayerItemResult(
            playerItem: playerItem,
            clipStartTimes: build.clipStartTimes,
            stillImagesBySourceIndex: stillImagesBySourceIndex
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

        // Create isolated copy of recipe with fresh effect state for export
        // This prevents stateful effects (like TextOverlayHook) from sharing state with preview
        let exportRecipe = recipe.copyForExport()
        let exportManager = RenderHookManager.forExport(recipe: exportRecipe)

        // Build composition with the export manager
        let builder = CompositionBuilder()
        let buildResult = await builder.build(
            recipe: exportRecipe,
            strategy: strategy,
            outputSize: config.outputSize,
            frameRate: config.frameRate,
            enableEffects: config.enableGlobalHooks,
            hookManager: exportManager
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

        // For montage with all still images, export as PNG instead of video
        if case .montage = strategy {
            let videoTracks = build.composition.tracks(withMediaType: .video)
            let hasActualVideoSegments = videoTracks.contains { track in
                track.segments.contains { !$0.isEmpty }
            }

            if !hasActualVideoSegments, let instruction = build.instructions.first {
                print("🎬 Montage with all still images - exporting as PNG")
                guard let montage = PhotoMontage(instruction: instruction, outputSize: config.outputSize) else {
                    return .failure(.exportFailed(
                        underlying: NSError(domain: "RenderEngine", code: 10,
                            userInfo: [NSLocalizedDescriptionKey: "No images for photo montage"])))
                }
                switch montage.exportPNG(to: outputURL) {
                case .success(let url):
                    print("✅ Export complete (PNG): \(url.lastPathComponent)")
                    return .success(url)
                case .failure(let error):
                    return .failure(.exportFailed(underlying: error))
                }
            }
        }

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
        exportSession.audioMix = build.audioMix
        exportSession.shouldOptimizeForNetworkUse = false

        print("🎬 Exporting to \(outputURL.lastPathComponent)...")

        // Export with progress tracking
        await exportSession.export()

        switch exportSession.status {
        case .completed:
            print("✅ Export complete: \(outputURL.lastPathComponent)")
            return .success(outputURL)

        case .failed:
            let error = exportSession.error ?? NSError(domain: "RenderEngine", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Export failed with unknown error"])
            print("🔴 Export failed: \(error)")

            // Check if file was actually created despite the error
            if FileManager.default.fileExists(atPath: outputURL.path) {
                print("⚠️  File exists despite error - treating as success")
                return .success(outputURL)
            }

            return .failure(.exportFailed(underlying: error))

        case .cancelled:
            print("⚠️  Export cancelled")
            return .failure(.exportFailed(
                underlying: NSError(domain: "RenderEngine", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Export cancelled"])
            ))

        default:
            print("🔴 Export unknown status: \(exportSession.status.rawValue)")
            return .failure(.exportFailed(
                underlying: NSError(domain: "RenderEngine", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Export ended with unknown status"])
            ))
        }
    }
}
