import Foundation
import AVFoundation
import CoreMedia

final class VideoSourcesLibrary {
    private(set) var files: [VideoFile] = []

    init(sourceFolders: [String]) {
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

        let allowedExtensions = ["mp4", "mov", "m4v", "webm"]

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
                    guard allowedExtensions.contains(ext) else { continue }

                    let asset = AVURLAsset(url: fileURL)
                    let duration = asset.duration

                    if asset.isPlayable, duration.isValid, duration.seconds > 0 {
                        results.append(VideoFile(url: fileURL, duration: duration))
                    }
                }
            } else {
                // Single-file case: treat it as one video file if extension matches
                let ext = url.pathExtension.lowercased()
                guard allowedExtensions.contains(ext) else { continue }

                let asset = AVAsset(url: url)
                let duration = asset.duration

                if asset.isPlayable, duration.isValid, duration.seconds > 0 {
                    results.append(VideoFile(url: url, duration: duration))
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

        let allowedExtensions = Set([
            "mov", "mp4", "m4v", "webm",
            "hevc", "avi", "mkv",
            "3gp", "3g2" // optional
        ])

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
            // Filter by extension
            let ext = fileURL.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }

            // File metadata
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                values.isRegularFile == true,
                values.isReadable == true else { continue }

            // Skip iCloud placeholders / stubs
            if let size = values.fileSize, size < 1024 { continue }

            // Try to load AVAsset and read duration
            let asset = AVAsset(url: fileURL)
            let duration = asset.duration

            guard duration.isValid, duration.seconds > 0 else { continue }

            results.append(VideoFile(url: fileURL, duration: duration))
        }

        self.files = results
        print("VideoSourcesLibrary: loaded \(results.count) original local videos from Photos originals/")
    }

    // MARK: - Random clip selection

    func randomClip(clipLength: Double) -> VideoClip? {
        guard let file = files.randomElement() else { return nil }

        let totalSeconds = file.duration.seconds
        guard totalSeconds > 0 else { return nil }

        let length = min(clipLength, totalSeconds)
        let maxStart = max(0.0, totalSeconds - length)
        let startSeconds = maxStart > 0 ? Double.random(in: 0...maxStart) : 0

        return VideoClip(
            file: file,
            startTime: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: length, preferredTimescale: 600)
        )
    }

    private func applyExclusions() {
        let store = ExclusionStore.shared
        files.removeAll { store.isExcluded(url: $0.url) }
    }

    // MARK: - Exclusions

    func exclude(file: VideoFile) {
        ExclusionStore.shared.add(url: file.url)
        files.removeAll { $0.url == file.url }
    }
}
