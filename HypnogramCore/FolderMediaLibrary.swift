//
//  MediaLibrary.swift
//  Hypnogram
//
//  Created by Loren Johnson on 15.11.25.
//


import Foundation
import AVFoundation
import CoreMedia

/// Loads video files from the configured source folders and
/// exposes helpers to get random clips from them.
final class MediaLibrary {
    private(set) var files: [VideoFile] = []

    init(config: HypnogramConfig) {
        loadFiles(from: config.sourceFolders)
    }

    /// Scan the given folders recursively for video files and
    /// record their durations using AVAsset.
    private func loadFiles(from folders: [String]) {
        let fileManager = FileManager.default
        var results: [VideoFile] = []

        for folder in folders {
            let folderURL = URL(fileURLWithPath: folder, isDirectory: true)

            guard let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                // Skip directories
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    continue
                }

                let ext = fileURL.pathExtension.lowercased()
                guard ["mp4", "mov", "m4v", "webm"].contains(ext) else { continue }

                let asset = AVAsset(url: fileURL)
                let duration = asset.duration
                if duration.isValid && duration.seconds > 0 {
                    let videoFile = VideoFile(url: fileURL, duration: duration)
                    results.append(videoFile)
                }
            }
        }

        self.files = results
    }

    /// Returns a random VideoClip of the desired length from any video file
    /// in the library. If the file is shorter than the requested clip length,
    /// the clip will be truncated to the file duration.
    func randomClip(clipLength: Double) -> VideoClip? {
        guard let file = files.randomElement() else { return nil }

        let totalSeconds = file.duration.seconds
        guard totalSeconds > 0 else { return nil }

        let length = min(clipLength, totalSeconds)
        let maxStart = max(0.0, totalSeconds - length)
        let startSeconds = maxStart > 0 ? Double.random(in: 0...maxStart) : 0

        let startTime = CMTime(seconds: startSeconds, preferredTimescale: 600)
        let duration = CMTime(seconds: length, preferredTimescale: 600)

        return VideoClip(file: file, startTime: startTime, duration: duration)
    }
}
