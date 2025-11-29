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

    /// Build a player item for preview
    func makePlayerItem(
        recipe: HypnogramRecipe,
        strategy: CompositionBuilder.TimelineStrategy,
        config: Config
    ) async -> Result<PlayerItemResult, RenderError> {

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

    // MARK: - Still Image Export

    private func exportAsImage(
        instruction: RenderInstruction,
        outputURL: URL,
        outputSize: CGSize
    ) -> Result<URL, RenderError> {

        // Composite all still images using same logic as FrameCompositor
        var result = CIImage.empty().cropped(to: CGRect(origin: .zero, size: outputSize))

        for (index, maybeImage) in instruction.stillImages.enumerated() {
            guard let image = maybeImage else { continue }

            var layerImage = image
            if index < instruction.transforms.count {
                layerImage = layerImage.transformed(by: instruction.transforms[index])
            }

            // Scale to fit output size
            let scaleX = outputSize.width / layerImage.extent.width
            let scaleY = outputSize.height / layerImage.extent.height
            let scale = max(scaleX, scaleY)
            layerImage = layerImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

            // Center
            let offsetX = (outputSize.width - layerImage.extent.width) / 2 - layerImage.extent.origin.x
            let offsetY = (outputSize.height - layerImage.extent.height) / 2 - layerImage.extent.origin.y
            layerImage = layerImage.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

            let blendMode = index < instruction.blendModes.count ? instruction.blendModes[index] : kBlendModeSourceOver
            result = ImageUtils.blend(layer: layerImage, over: result, mode: blendMode)
        }

        result = result.cropped(to: CGRect(origin: .zero, size: outputSize))

        // Render to CGImage and save as PNG
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(result, from: result.extent) else {
            return .failure(.exportFailed(
                underlying: NSError(domain: "RenderEngine", code: 10,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
            ))
        }

        let imageURL = outputURL.deletingPathExtension().appendingPathExtension("png")
        let destination = CGImageDestinationCreateWithURL(imageURL as CFURL, UTType.png.identifier as CFString, 1, nil)
        guard let dest = destination else {
            return .failure(.exportFailed(
                underlying: NSError(domain: "RenderEngine", code: 11,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
            ))
        }

        CGImageDestinationAddImage(dest, cgImage, nil)

        if CGImageDestinationFinalize(dest) {
            print("✅ Export complete (PNG): \(imageURL.lastPathComponent)")
            return .success(imageURL)
        } else {
            return .failure(.exportFailed(
                underlying: NSError(domain: "RenderEngine", code: 12,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to write PNG"])
            ))
        }
    }
}
