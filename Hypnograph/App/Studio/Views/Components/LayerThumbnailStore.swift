import AppKit
import AVFoundation
import CoreImage
import CoreMedia
import HypnoCore

@MainActor
final class LayerThumbnailStore: ObservableObject {
    private var cache: [UUID: NSImage] = [:]
    private var inFlight: Set<UUID> = []

    func image(for layer: Layer) -> NSImage? {
        cache[layer.mediaClip.file.id]
    }

    func loadIfNeeded(for layer: Layer, targetSize: CGSize) {
        let id = layer.mediaClip.file.id
        guard cache[id] == nil else { return }
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)

        Task {
            let image = await Self.generateThumbnail(for: layer.mediaClip, targetSize: targetSize)
            await MainActor.run {
                self.inFlight.remove(id)
                if let image {
                    self.cache[id] = image
                    self.objectWillChange.send()
                }
            }
        }
    }

    nonisolated private static func generateThumbnail(for clip: MediaClip, targetSize: CGSize) async -> NSImage? {
        await Task.detached(priority: .utility) {
            switch clip.file.source {
            case .url(let url):
                return thumbnailFromURL(url, mediaKind: clip.file.mediaKind, time: clip.startTime, targetSize: targetSize)

            case .external(let identifier):
                return await thumbnailFromExternal(identifier: identifier, mediaKind: clip.file.mediaKind, time: clip.startTime, targetSize: targetSize)
            }
        }.value
    }

    nonisolated private static func thumbnailFromURL(
        _ url: URL,
        mediaKind: MediaKind,
        time: CMTime,
        targetSize: CGSize
    ) -> NSImage? {
        switch mediaKind {
        case .image:
            guard let image = NSImage(contentsOf: url) else { return nil }
            return image

        case .video:
            let asset = AVAsset(url: url)
            return thumbnailFromAVAsset(asset, time: time, targetSize: targetSize)
        }
    }

    nonisolated private static func thumbnailFromExternal(
        identifier: String,
        mediaKind: MediaKind,
        time: CMTime,
        targetSize: CGSize
    ) async -> NSImage? {
        switch mediaKind {
        case .image:
            guard let ci = await HypnoCoreHooks.shared.resolveExternalImage?(identifier) else { return nil }
            return nsImage(from: ci)

        case .video:
            guard let asset = await HypnoCoreHooks.shared.resolveExternalVideo?(identifier) else { return nil }
            return thumbnailFromAVAsset(asset, time: time, targetSize: targetSize)
        }
    }

    nonisolated private static func thumbnailFromAVAsset(_ asset: AVAsset, time: CMTime, targetSize: CGSize) -> NSImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = targetSize

        let requestedTime = time.isValid && time.seconds.isFinite ? time : .zero
        guard let cg = try? generator.copyCGImage(at: requestedTime, actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: targetSize)
    }

    nonisolated private static func nsImage(from ciImage: CIImage) -> NSImage? {
        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: cg, size: ciImage.extent.size)
    }
}
