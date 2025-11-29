import Foundation
import AVFoundation
import CoreMedia
import CoreImage

final class VideoSourcesLibrary {
    // MARK: - Lazy Loading Optimization
    // For large libraries (5000+ files), we use a two-tier approach:
    // 1. Lightweight index: just URLs and media kind (fast startup, low memory)
    // 2. Lazy metadata loading: only load AVAsset/duration when file is selected

    private struct FileEntry {
        let url: URL
        let mediaKind: MediaKind
    }

    private var fileIndex: [FileEntry] = []

    /// Legacy accessor for compatibility (returns empty - not used anymore)
    private(set) var files: [VideoFile] = []

    /// Files that have failed validation at selection time (in-memory only).
    private var badURLs = Set<URL>()

    /// Whether to allow still images (for performance testing)
    private let allowStillImages: Bool

    let allowedPhotoExtensions = Set([
        "jpeg", "jpg", "png", "heic", "gif"
    ])

    let allowVideoExtensions = Set([
        "mov", "mp4", "m4v", "webm",
        "hevc", "avi", "mkv",
        "3gp", "3g2"
    ])

    init(sourceFolders: [String], allowStillImages: Bool = true) {
        self.allowStillImages = allowStillImages
        if sourceFolders.isEmpty {
            // No explicit sources → default to Photos library videos
            loadFilesFromPhotosLibrary()
        } else {
            // Explicit folders / files → current behavior
            loadFiles(from: sourceFolders)
        }
        applyExclusions()
    }

    // MARK: - File system sources

    private func loadFiles(from sources: [String]) {
        let fileManager = FileManager.default
        var results: [FileEntry] = []

        for path in sources {
            let url = URL(fileURLWithPath: path)

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                // Directory case: recurse and collect URLs only (no AVAsset creation!)
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: nil
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir),
                       isDir.boolValue {
                        continue
                    }

                    let ext = fileURL.pathExtension.lowercased()

                    if allowVideoExtensions.contains(ext) {
                        // Just store URL + kind, no duration loading!
                        results.append(FileEntry(url: fileURL, mediaKind: .video))
                    } else if allowStillImages && allowedPhotoExtensions.contains(ext) {
                        results.append(FileEntry(url: fileURL, mediaKind: .image))
                    }
                }
            } else {
                // Single-file case
                let ext = url.pathExtension.lowercased()

                if allowVideoExtensions.contains(ext) {
                    results.append(FileEntry(url: url, mediaKind: .video))
                } else if allowStillImages && allowedPhotoExtensions.contains(ext) {
                    results.append(FileEntry(url: url, mediaKind: .image))
                }
            }
        }

        self.fileIndex = results
        applyExclusions()
    }

    // MARK: - Photos library fallback (raw originals scan)

    private func loadFilesFromPhotosLibrary() {
        let fm = FileManager.default
        let picturesDir = fm.urls(for: .picturesDirectory, in: .userDomainMask).first!

        let photosLibURL = picturesDir.appendingPathComponent(
            "Photos Library.photoslibrary",
            isDirectory: true
        )

        let originalsURL = photosLibURL.appendingPathComponent("originals", isDirectory: true)

        guard fm.fileExists(atPath: originalsURL.path) else {
            print("VideoSourcesLibrary: Originals folder not found at \(originalsURL.path)")
            self.fileIndex = []
            return
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .isReadableKey
        ]

        var results: [FileEntry] = []

        guard let enumerator = fm.enumerator(
            at: originalsURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            self.fileIndex = []
            return
        }

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()

            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true,
                  values.isReadable == true else { continue }

            // Skip iCloud placeholders / stubs
            if let size = values.fileSize, size < 1024 { continue }

            if allowVideoExtensions.contains(ext) {
                // Just store URL + kind, no AVAsset creation!
                results.append(FileEntry(url: fileURL, mediaKind: .video))
            } else if allowStillImages && allowedPhotoExtensions.contains(ext) {
                results.append(FileEntry(url: fileURL, mediaKind: .image))
            }
        }

        self.fileIndex = results
        print("VideoSourcesLibrary: indexed \(results.count) media files from Photos originals/")
    }

    // MARK: - Random clip selection (with lazy validation for video + image)

    func randomClip(clipLength: Double) -> VideoClip? {
        // Consider *all* files except those already marked bad.
        let candidates = fileIndex.filter { !badURLs.contains($0.url) }
        guard !candidates.isEmpty else { return nil }

        let maxAttempts = min(32, max(candidates.count * 2, 1))

        for _ in 0..<maxAttempts {
            guard let entry = candidates.randomElement() else { break }

            switch entry.mediaKind {
            case .video:
                // Use the asset duration, since that’s authoritative.
                let asset = AVURLAsset(url: entry.url)
                let totalSeconds = asset.duration.seconds

                // Validate
                guard totalSeconds > 0,
                      asset.isPlayable,
                      asset.tracks(withMediaType: .video).first != nil else {
                    badURLs.insert(entry.url)
                    continue
                }

                let length = min(clipLength, totalSeconds)
                let maxStart = max(0.0, totalSeconds - length)
                let startSeconds = maxStart > 0 ? Double.random(in: 0...maxStart) : 0

                return VideoClip(
                    file: VideoFile(
                        url: entry.url,
                        mediaKind: .video,
                        duration: CMTime(seconds: totalSeconds, preferredTimescale: 600)
                    ),
                    startTime: CMTime(seconds: startSeconds, preferredTimescale: 600),
                    duration: CMTime(seconds: length, preferredTimescale: 600)
                )

            case .image:
                // Validate image can be loaded using cache (ensures proper pixel format)
                guard let image = StillImageCache.ciImage(for: entry.url),
                      !image.extent.isEmpty else {
                    badURLs.insert(entry.url)
                    continue
                }

                // Time-invariant: we just pretend this still lasts as long as the clipLength.
                let length = max(clipLength, 0.1)
                return VideoClip(
                    file: VideoFile(
                        url: entry.url,
                        mediaKind: .image,
                        duration: CMTime(seconds: length, preferredTimescale: 600)
                    ),
                    startTime: .zero,
                    duration: CMTime(seconds: length, preferredTimescale: 600)
                )
            }
        }

        return nil
    }

    private func applyExclusions() {
        let store = ExclusionStore.shared
        fileIndex.removeAll { store.isExcluded(url: $0.url) }
        // Note: we intentionally *do not* apply `badURLs` here; those are runtime-only.
    }

    // MARK: - Exclusions (user-driven only)

    func exclude(file: VideoFile) {
        // This is reserved for explicit user choice ("X = Add to Exclude List"),
        // not for automatic validation.
        ExclusionStore.shared.add(url: file.url)
        fileIndex.removeAll { $0.url == file.url }
    }
}
