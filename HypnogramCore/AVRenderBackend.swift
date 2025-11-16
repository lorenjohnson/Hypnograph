import Foundation
import AVFoundation
import CoreMedia

/// RenderBackend implementation that uses AVFoundation to render full Hypnograms:
/// - one track per layer
/// - custom CoreImage compositor applying per-layer blend modes.
final class AVRenderBackend: RenderBackend {
    private let outputFolder: URL

    init(outputFolder: URL) {
        self.outputFolder = outputFolder
    }

    func enqueue(recipe: HypnogramRecipe, completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.render(recipe: recipe, completion: completion)
        }
    }

    private func render(recipe: HypnogramRecipe, completion: @escaping (Result<URL, Error>) -> Void) {
        // Ensure we have at least one layer.
        guard !recipe.layers.isEmpty else {
            completion(.failure(NSError(
                domain: "AVRenderBackend",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Empty HypnogramRecipe"]
            )))
            return
        }

        let composition = AVMutableComposition()

        var trackIDs: [CMPersistentTrackID] = []
        var blendModes: [String] = []

        var renderSize: CGSize?
        var maxDuration: CMTime = .zero

        for (index, layer) in recipe.layers.enumerated() {
            let clip = layer.clip
            let asset = AVAsset(url: clip.file.url)

            guard let srcTrack = asset.tracks(withMediaType: .video).first else {
                continue
            }

            // Assign a stable track ID for this layer.
            let trackID = CMPersistentTrackID(index + 1)
            guard let compTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: trackID
            ) else {
                continue
            }

            let timeRange = CMTimeRange(start: clip.startTime, duration: clip.duration)

            do {
                try compTrack.insertTimeRange(timeRange, of: srcTrack, at: .zero)
            } catch {
                print("AVRenderBackend: failed to insert time range for layer \(index): \(error)")
                continue
            }

            compTrack.preferredTransform = srcTrack.preferredTransform

            trackIDs.append(compTrack.trackID)
            blendModes.append(layer.blendMode.name)

            // Determine render size from the first valid track.
            if renderSize == nil {
                let natural = srcTrack.naturalSize
                let transform = srcTrack.preferredTransform
                let transformed = natural.applying(transform)
                renderSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
            }

            let clipEnd = CMTimeAdd(.zero, clip.duration)
            if clipEnd > maxDuration {
                maxDuration = clipEnd
            }
        }

        guard
            !trackIDs.isEmpty,
            let finalRenderSize = renderSize,
            maxDuration > .zero
        else {
            completion(.failure(NSError(
                domain: "AVRenderBackend",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No valid video tracks for rendering"]
            )))
            return
        }

        // Build video composition with our custom compositor.
        let instruction = HypnogramVideoCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: maxDuration),
            layerTrackIDs: trackIDs,
            blendModes: blendModes
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = HypnogramVideoCompositor.self
        videoComposition.renderSize = finalRenderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        // Ensure output directory exists.
        do {
            try FileManager.default.createDirectory(
                at: outputFolder,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            completion(.failure(error))
            return
        }

        let filename = "hypnogram-\(UUID().uuidString).mp4"
        let outputURL = outputFolder.appendingPathComponent(filename)

        // Remove existing file if present.
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPreset1920x1080
        ) ?? AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            completion(.failure(NSError(
                domain: "AVRenderBackend",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAssetExportSession"]
            )))
            return
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition

        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                print("AVRenderBackend: export completed → \(outputURL.path)")
                completion(.success(outputURL))
            case .failed, .cancelled:
                let error = exportSession.error ?? NSError(
                    domain: "AVRenderBackend",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Export failed or cancelled"]
                )
                print("AVRenderBackend: export failed/cancelled: \(error)")
                completion(.failure(error))
            default:
                let error = exportSession.error ?? NSError(
                    domain: "AVRenderBackend",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected export status: \(exportSession.status)"]
                )
                print("AVRenderBackend: unexpected export status: \(exportSession.status)")
                completion(.failure(error))
            }
        }
    }
}
