import Foundation
import AVFoundation
import CoreMedia

public final class VideoSourcesLibrary {
    public private(set) var files: [VideoFile] = []

    public init(sourceFolders: [String]) {
        loadFiles(from: sourceFolders)
    }

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

                    let asset = AVAsset(url: fileURL)
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

                if duration.isValid, duration.seconds > 0 {
                    results.append(VideoFile(url: url, duration: duration))
                }
            }
        }

        self.files = results
    }

    public func randomClip(clipLength: Double) -> VideoClip? {
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
