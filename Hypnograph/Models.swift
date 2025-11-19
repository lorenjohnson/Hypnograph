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
public struct VideoFile: Identifiable {
    public let id: UUID
    public let url: URL
    public let duration: CMTime

    public init(id: UUID = UUID(), url: URL, duration: CMTime) {
        self.id = id
        self.url = url
        self.duration = duration
    }
}

/// A specific slice (start + length) from a VideoFile.
public struct VideoClip {
    public let file: VideoFile
    public let startTime: CMTime
    public let duration: CMTime

    public init(file: VideoFile, startTime: CMTime, duration: CMTime) {
        self.file = file
        self.startTime = startTime
        self.duration = duration
    }
}

/// Represents a blend mode (Multiply, SoftLight, Overlay, etc.)
/// We take a simple name from settings (e.g. "multiply") and can
/// derive both:
/// - a stable key/name ("multiply") for UI / JSON
/// - the CoreImage filter name (e.g. "CIMultiplyBlendMode") for rendering
public struct BlendMode {
    /// Simple key from settings, e.g. "multiply", "softlight", "overlay".
    public let key: String

    /// Convenience init to keep existing `BlendMode(name: ...)` calls working.
    public init(name: String) {
        self.key = name
    }

    /// Optional direct key-based init if you ever need it.
    public init(key: String) {
        self.key = key
    }

    /// Name used everywhere else (UI label, JSON, etc.).
    public var name: String {
        key
    }

    /// CoreImage filter name for this blend mode.
    public var ciFilterName: String {
        switch key.lowercased() {
        case "multiply":
            return "CIMultiplyBlendMode"
        case "screen":
            return "CIScreenBlendMode"
        case "overlay":
            return "CIOverlayBlendMode"
        case "softlight", "soft_light", "soft-light":
            return "CISoftLightBlendMode"
        case "hardlight", "hard_light", "hard-light":
            return "CIHardLightBlendMode"
        case "darken":
            return "CIDarkenBlendMode"
        case "lighten":
            return "CILightenBlendMode"
        case "difference":
            return "CIDifferenceBlendMode"
        case "exclusion":
            return "CIExclusionBlendMode"
        case "colordodge", "color_dodge", "color-dodge":
            return "CIColorDodgeBlendMode"
        case "colorburn", "color_burn", "color-burn":
            return "CIColorBurnBlendMode"
        case "hue":
            return "CIHueBlendMode"
        case "saturation":
            return "CISaturationBlendMode"
        case "color":
            return "CIColorBlendMode"
        case "luminosity":
            return "CILuminosityBlendMode"
        default:
            // Safe fallback: normal compositing
            return "CISourceOverCompositing"
        }
    }
}

/// One layer of a hypnogram: a clip + its blend mode.
public struct HypnogramLayer {
    public let clip: VideoClip
    public let blendMode: BlendMode

    public init(clip: VideoClip, blendMode: BlendMode) {
        self.clip = clip
        self.blendMode = blendMode
    }
}

/// A complete “hypnogram” recipe: ordered layers of clip + blend mode
/// plus the target render duration for the composition.
public struct HypnogramRecipe {
    public let layers: [HypnogramLayer]
    public let targetDuration: CMTime

    public init(layers: [HypnogramLayer], targetDuration: CMTime) {
        self.layers = layers
        self.targetDuration = targetDuration
    }
}
