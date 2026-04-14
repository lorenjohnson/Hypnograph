import AppKit
import HypnoCore

@MainActor
final class TimelineThumbnailStore: ObservableObject {
    private var cache: [UUID: NSImage] = [:]
    private var inFlight: Set<UUID> = []

    func image(for layer: Layer) -> NSImage? {
        cache[layer.mediaClip.file.id]
    }

    func hasMissingLocalSource(for layer: Layer) -> Bool {
        guard case .url(let url) = layer.mediaClip.file.source else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    func loadIfNeeded(for layer: Layer, targetSize: CGSize) {
        let id = layer.mediaClip.file.id
        guard cache[id] == nil else { return }
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)

        Task(priority: ThumbnailWorkPolicy.mediaThumbnailTaskPriority) {
            let image = await MediaThumbnailGenerator.makeImage(
                source: layer.mediaClip.file.source,
                mediaKind: layer.mediaClip.file.mediaKind,
                sourceDurationSeconds: max(0.1, layer.mediaClip.file.duration.seconds),
                time: layer.mediaClip.startTime,
                maximumSize: targetSize
            )
            await MainActor.run {
                self.inFlight.remove(id)
                if let image {
                    self.cache[id] = image
                    self.objectWillChange.send()
                }
            }
        }
    }
}
