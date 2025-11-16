//
//  VideoFile.swift
//  Hypnogram
//
//  Created by Loren Johnson on 15.11.25.
//


import Foundation
import CoreMedia

// MARK: - Core Data Models

/// A single video file on disk that we can select clips from.
struct VideoFile: Identifiable {
    let id = UUID()
    let url: URL
    let duration: CMTime
}

/// A specific slice (start + length) from a VideoFile.
struct VideoClip {
    let file: VideoFile
    let startTime: CMTime
    let duration: CMTime
}

/// Represents a blend mode (Multiply, SoftLight, Overlay, etc.)
/// For now it's just a name; later we can attach native shader/Metal identifiers.
struct BlendMode {
    let name: String
}

/// One layer of a hypnogram: a clip + its blend mode.
struct HypnogramLayer {
    let clip: VideoClip
    let blendMode: BlendMode
}

/// A complete “hypnogram” recipe: ordered layers of clip + blend mode.
struct HypnogramRecipe {
    let layers: [HypnogramLayer]
}
