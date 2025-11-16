import Foundation
import AVFoundation
import CoreMedia

final class FolderMediaLibrary: ClipLibrary {
    private(set) var files: [VideoFile] = []

    init(config: HypnogramConfig) {
        loadFiles(from: config.sourceFolders)
    }

    private func loadFiles(from folders: [String]) {
        let fileManager = FileManager.default
        var results: [VideoFile] = []

        for folder in folders {
            let folderURL = URL(fileURLWithPath: folder, isDirectory: true)

            guard let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: nil
            ) else { continue }

            for case let fileURL as URL in enumerator {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                   isDirectory.boolValue { continue }

                let ext = fileURL.pathExtension.lowercased()
                guard ["mp4", "mov", "m4v", "webm"].contains(ext) else { continue }

                let asset = AVAsset(url: fileURL)
                let duration = asset.duration

                if duration.isValid, duration.seconds > 0 {
                    results.append(VideoFile(url: fileURL, duration: duration))
                }
            }
        }

        self.files = results
    }

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
}
