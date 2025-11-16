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
/// We take a simple name from config (e.g. "multiply") and can
/// derive both:
/// - a stable key/name ("multiply") for UI / JSON
/// - the CoreImage filter name (e.g. "CIMultiplyBlendMode") for rendering
struct BlendMode {
    /// Simple key from config, e.g. "multiply", "softlight", "overlay".
    let key: String

    /// Convenience init to keep existing `BlendMode(name: ...)` calls working.
    init(name: String) {
        self.key = name
    }

    /// Name used everywhere else (UI label, JSON, etc.).
    var name: String {
        key
    }

    /// CoreImage filter name for this blend mode.
    /// These are the CI blend filters, e.g. "CIMultiplyBlendMode".
    var ciFilterName: String {
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
struct HypnogramLayer {
    let clip: VideoClip
    let blendMode: BlendMode
}

/// A complete “hypnogram” recipe: ordered layers of clip + blend mode
/// plus the target render duration for the composition.
struct HypnogramRecipe {
    let layers: [HypnogramLayer]
    let targetDuration: CMTime
}
