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
enum ModeType: String, Codable {
    case montage
    case sequence
    case divine
}

/// Mode-specific configuration payloads that can be attached to a HypnogramRecipe.
///
/// Each mode defines its own config type that conforms to this protocol and can be
/// serialized into the recipe via JSON (stored as opaque Data).
protocol ModeConfig: Codable {
    /// The mode this config belongs to.
    static var modeType: ModeType { get }
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
///
/// NOTE: `blendMode` is *used only by Montage mode* for multi-layer compositing.
/// Other modes can safely ignore it; they don't need to branch on it.
struct HypnogramSource {
    var clip: VideoClip
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

/// A complete “hypnogram” recipe: ordered sources of clip (+ optional blend mode)
/// plus the target render duration for the composition.
///
/// Additionally, a recipe can carry a *mode-specific* configuration payload, which
/// is an opaque JSON blob owned by the active mode (e.g. Montage’s blend-mode stack).
struct HypnogramRecipe {
    var sources: [HypnogramSource]
    var targetDuration: CMTime

    /// The mode this recipe is primarily configured for (if any).
    var mode: ModeType?

    /// Opaque JSON for the active mode’s configuration.
    private var modeConfigData: Data?

    init(
        sources: [HypnogramSource],
        targetDuration: CMTime,
        mode: ModeType? = nil,
        modeConfigData: Data? = nil
    ) {
        self.sources = sources
        self.targetDuration = targetDuration
        self.mode = mode
        self.modeConfigData = modeConfigData
    }

    /// Decode a strongly-typed mode configuration if it matches the recipe’s mode.
    func modeConfig<T: ModeConfig>(_ type: T.Type) -> T? {
        guard
            let mode,
            mode == T.modeType,
            let data = modeConfigData
        else {
            return nil
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("HypnogramRecipe: failed to decode mode config \(T.self): \(error)")
            return nil
        }
    }

    /// Attach a strongly-typed mode configuration to this recipe.
    ///
    /// This overwrites any existing mode + config on the recipe.
    mutating func setModeConfig<T: ModeConfig>(_ config: T) {
        mode = T.modeType
        do {
            modeConfigData = try JSONEncoder().encode(config)
        } catch {
            print("HypnogramRecipe: failed to encode mode config \(T.self): \(error)")
            modeConfigData = nil
        }
    }
}
