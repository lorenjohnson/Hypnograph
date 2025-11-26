import Foundation
import AVFoundation
import CoreMedia
import CoreImage

final class VideoSourcesLibrary {
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
        var results: [VideoFile] = []

        for path in sources {
            let url = URL(fileURLWithPath: path)

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                // Directory case: recurse like before
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
                        // Light registration: real validation happens on selection.
                        let asset = AVURLAsset(url: fileURL)
                        let duration = asset.duration
                        results.append(
                            VideoFile(
                                url: fileURL,
                                mediaKind: .video,
                                duration: duration
                            )
                        )
                    } else if allowStillImages && allowedPhotoExtensions.contains(ext) {
                        // Only load still images if allowed (for performance testing)
                        let syntheticDuration = CMTime(seconds: 5.0, preferredTimescale: 600)
                        results.append(
                            VideoFile(
                                url: fileURL,
                                mediaKind: .image,
                                duration: syntheticDuration
                            )
                        )
                    }
                }
            } else {
                // Single-file case
                let ext = url.pathExtension.lowercased()

                if allowVideoExtensions.contains(ext) {
                    let asset = AVURLAsset(url: url)
                    let duration = asset.duration
                    results.append(
                        VideoFile(
                            url: url,
                            mediaKind: .video,
                            duration: duration
                        )
                    )
                } else if allowStillImages && allowedPhotoExtensions.contains(ext) {
                    // Only load still images if allowed (for performance testing)
                    let syntheticDuration = CMTime(seconds: 5.0, preferredTimescale: 600)
                    results.append(
                        VideoFile(
                            url: url,
                            mediaKind: .image,
                            duration: syntheticDuration
                        )
                    )
                }
            }
        }

        self.files = results
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
            self.files = []
            return
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .isReadableKey
        ]

        var results: [VideoFile] = []

        guard let enumerator = fm.enumerator(
            at: originalsURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            self.files = []
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
                // Registration only; validate lazily.
                let asset = AVURLAsset(url: fileURL)
                let duration = asset.duration
                results.append(
                    VideoFile(
                        url: fileURL,
                        mediaKind: .video,
                        duration: duration
                    )
                )
            } else if allowStillImages && allowedPhotoExtensions.contains(ext) {
                // Only load still images if allowed (for performance testing)
                let syntheticDuration = CMTime(seconds: 5.0, preferredTimescale: 600)
                results.append(
                    VideoFile(
                        url: fileURL,
                        mediaKind: .image,
                        duration: syntheticDuration
                    )
                )
            }
        }

        self.files = results
        print("VideoSourcesLibrary: loaded \(results.count) local media files from Photos originals/")
    }

    // MARK: - Random clip selection (with lazy validation for video + image)

    func randomClip(clipLength: Double) -> VideoClip? {
        // Consider *all* files except those already marked bad.
        let candidates = files.filter { !badURLs.contains($0.url) }
        guard !candidates.isEmpty else { return nil }

        let maxAttempts = min(32, max(candidates.count * 2, 1))

        for _ in 0..<maxAttempts {
            guard let file = candidates.randomElement() else { break }

            // Validate the chosen file according to its media kind.
            if !validate(file: file) {
                badURLs.insert(file.url)
                continue
            }

            switch file.mediaKind {
            case .video:
                // Use the asset duration, since that’s authoritative.
                let asset = AVURLAsset(url: file.url)
                let totalSeconds = asset.duration.seconds
                guard totalSeconds > 0 else {
                    badURLs.insert(file.url)
                    continue
                }

                let length = min(clipLength, totalSeconds)
                let maxStart = max(0.0, totalSeconds - length)
                let startSeconds = maxStart > 0 ? Double.random(in: 0...maxStart) : 0

                return VideoClip(
                    file: VideoFile(
                        id: file.id,
                        url: file.url,
                        mediaKind: .video,
                        duration: CMTime(seconds: totalSeconds, preferredTimescale: 600)
                    ),
                    startTime: CMTime(seconds: startSeconds, preferredTimescale: 600),
                    duration: CMTime(seconds: length, preferredTimescale: 600)
                )

            case .image:
                // Time-invariant: we just pretend this still lasts as long as the clipLength.
                let length = max(clipLength, 0.1)
                return VideoClip(
                    file: file,
                    startTime: .zero,
                    duration: CMTime(seconds: length, preferredTimescale: 600)
                )
            }
        }

        return nil
    }

    /// Shared validator for both video + image files.
    /// - Videos: must be playable, have a video track, and positive duration.
    /// - Images: must decode into a non-empty CIImage.
    func validate(file: VideoFile) -> Bool {
        switch file.mediaKind {
        case .video:
            let asset = AVURLAsset(url: file.url)

            guard asset.isPlayable else { return false }
            guard let track = asset.tracks(withMediaType: .video).first else { return false }

            let duration = track.timeRange.duration
            guard duration.isValid, duration.seconds > 0 else { return false }

            return true

        case .image:
            guard let image = CIImage(contentsOf: file.url) else {
                return false
            }
            return !image.extent.isEmpty
        }
    }

    private func applyExclusions() {
        let store = ExclusionStore.shared
        files.removeAll { store.isExcluded(url: $0.url) }
        // Note: we intentionally *do not* apply `badURLs` here; those are runtime-only.
    }

    // MARK: - Exclusions (user-driven only)

    func exclude(file: VideoFile) {
        // This is reserved for explicit user choice ("X = Add to Exclude List"),
        // not for automatic validation.
        ExclusionStore.shared.add(url: file.url)
        files.removeAll { $0.url == file.url }
    }
}
