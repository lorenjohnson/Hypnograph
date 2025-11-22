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

/// Represents a blend mode (Multiply, SoftLight, Overlay, etc.)
/// We take a simple name from settings (e.g. "multiply") and can
/// derive both:
/// - a stable key/name ("multiply") for UI / JSON
/// - the CoreImage filter name (e.g. "CIMultiplyBlendMode") for rendering
struct BlendMode {
    /// Simple key from settings, e.g. "multiply", "softlight", "overlay".
    let key: String

    /// Convenience init to keep existing `BlendMode(name: ...)` calls working.
    init(name: String) {
        self.key = name
    }

    /// Optional direct key-based init if you ever need it.
    init(key: String) {
        self.key = key
    }

    /// Name used everywhere else (UI label, JSON, etc.).
    var name: String {
        key
    }

    /// CoreImage filter name for this blend mode.
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

/// One source of a hypnogram: clip + optional blend mode + transform + effects.
struct HypnogramSource {
    var clip: VideoClip
    var blendMode: BlendMode
    var transform: CGAffineTransform
    var effects: [RenderHook]

    init(
        clip: VideoClip,
        blendMode: BlendMode = BlendMode(key: "normal"),
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
