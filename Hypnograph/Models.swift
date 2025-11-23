//
//  Models.swift
//  Hypnogram
//
//  Created by Loren Johnson on 15.11.25.
//

import Foundation
import CoreMedia

// MARK: - Mode Types

/// Available mode types for the application
enum ModeType {
    case montage
    case sequence
    case divine
}

// MARK: - Core Data Models

/// A single video file on disk that we can select clips from.
struct VideoFile: Identifiable {
    let id: UUID
    let url: URL
    let duration: CMTime

    init(id: UUID = UUID(), url: URL, duration: CMTime) {
        self.id = id
        self.url = url
        self.duration = duration
    }
}

/// A specific slice (start + length) from a VideoFile.
struct VideoClip {
    let file: VideoFile
    let startTime: CMTime
    let duration: CMTime

    init(file: VideoFile, startTime: CMTime, duration: CMTime) {
        self.file = file
        self.startTime = startTime
        self.duration = duration
    }
}

/// Represents a Core Image blend mode used in Montage mode.
/// We store the CI filter name directly (e.g. "CIScreenBlendMode").
struct BlendMode: Equatable {
    /// Full Core Image filter name.
    let ciFilterName: String

    init(ciFilterName: String) {
        self.ciFilterName = ciFilterName
    }

    /// Human-readable name derived from the filter name.
    ///  - "CIScreenBlendMode"      → "Screen"
    ///  - "CISourceOverCompositing"→ "SourceOver"
    var displayName: String {
        var name = ciFilterName

        if name.hasPrefix("CI") {
            name.removeFirst(2)
        }

        if name.hasSuffix("BlendMode") {
            name.removeLast("BlendMode".count)
        } else if name.hasSuffix("Compositing") {
            name.removeLast("Compositing".count)
        }

        // Capitalize first letter for HUD niceness
        if let first = name.first {
            let rest = name.dropFirst()
            return String(first).uppercased() + rest
        } else {
            return name
        }
    }

    /// Convenience for a “normal” source-over composition.
    static let sourceOver = BlendMode(ciFilterName: "CISourceOverCompositing")
}

/// One source of a hypnogram: clip + optional blend mode + transform + effects.
struct HypnogramSource {
    var clip: VideoClip
    // TODO: All things blendMode are Montage specific. I would like to make this
    // something that Montage mode extends on this struct vs forcing every mode to
    // check for its existence.
    var blendMode: BlendMode
    var transform: CGAffineTransform
    var effects: [RenderHook]

    init(
        clip: VideoClip,
        blendMode: BlendMode = .sourceOver,
        transform: CGAffineTransform = .identity,
        effects: [RenderHook] = []
    ) {
        self.clip = clip
        self.blendMode = blendMode
        self.transform = transform
        self.effects = effects
    }
}

/// A complete “hypnogram” recipe: ordered sources of clip + blend mode
/// plus the target render duration for the composition.
struct HypnogramRecipe {
    let sources: [HypnogramSource]
    let targetDuration: CMTime

    init(sources: [HypnogramSource], targetDuration: CMTime) {
        self.sources = sources
        self.targetDuration = targetDuration
    }
}
