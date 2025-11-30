//
//  BlendNormalization.swift
//  Hypnograph
//
//  Automatic luminance/contrast normalization for multi-layer blend mode compositing.
//  Follows the RenderHook pattern: swappable strategies that can be tuned or replaced.
//
//  Theory: Non-linear blend modes compound exponentially:
//    - Screen: result = 1 - (1-a)(1-b) → pushes toward white
//    - Multiply: result = a * b → pushes toward black
//  Strategies apply per-layer opacity compensation and/or post-composition
//  normalization to maintain stable luminance and contrast.
//

import CoreImage

// MARK: - Blend Mode Classification

/// Categorizes blend modes by their luminance behavior
enum BlendModeFamily {
    /// Lightening modes: Screen, ColorDodge, Lighten, Add
    /// These push luminance toward 1.0 exponentially when stacked
    case lightening

    /// Darkening modes: Multiply, ColorBurn, Darken
    /// These push luminance toward 0.0 exponentially when stacked
    case darkening

    /// Contrast modes: Overlay, SoftLight, HardLight
    /// These increase contrast but don't systematically drift luminance
    case contrast

    /// Neutral modes: SourceOver, Normal
    /// No luminance compensation needed
    case neutral
}

enum BlendModeClassifier {

    static func family(for mode: String) -> BlendModeFamily {
        switch mode {
        // Lightening family
        case "CIScreenBlendMode", "CIColorDodgeBlendMode", "CILightenBlendMode",
             "CIAdditionCompositing", "CILinearDodgeBlendMode":
            return .lightening

        // Darkening family
        case "CIMultiplyBlendMode", "CIColorBurnBlendMode", "CIDarkenBlendMode",
             "CILinearBurnBlendMode":
            return .darkening

        // Contrast family
        case "CIOverlayBlendMode", "CISoftLightBlendMode", "CIHardLightBlendMode",
             "CIVividLightBlendMode", "CIPinLightBlendMode":
            return .contrast

        // Neutral / default
        default:
            return .neutral
        }
    }

    /// Analyze blend modes to determine the dominant behavior
    static func analyze(blendModes: [String]) -> BlendModeAnalysis {
        var lightening = 0
        var darkening = 0
        var contrast = 0

        // Skip first mode (base layer is always SourceOver)
        for mode in blendModes.dropFirst() {
            switch family(for: mode) {
            case .lightening: lightening += 1
            case .darkening: darkening += 1
            case .contrast: contrast += 1
            case .neutral: break
            }
        }

        return BlendModeAnalysis(
            layerCount: blendModes.count,
            lighteningCount: lightening,
            darkeningCount: darkening,
            contrastCount: contrast
        )
    }
}

/// Summary of blend mode usage in a composite
struct BlendModeAnalysis {
    let layerCount: Int
    let lighteningCount: Int
    let darkeningCount: Int
    let contrastCount: Int

    /// True if there are enough non-neutral layers to warrant compensation
    var needsCompensation: Bool {
        layerCount >= 3 && (lighteningCount > 0 || darkeningCount > 0)
    }

    /// Dominant drift direction (if any)
    var dominantFamily: BlendModeFamily? {
        if lighteningCount > darkeningCount && lighteningCount > 0 {
            return .lightening
        } else if darkeningCount > lighteningCount && darkeningCount > 0 {
            return .darkening
        } else if lighteningCount > 0 && darkeningCount > 0 {
            return .contrast  // Mixed
        }
        return nil
    }
}

// MARK: - Normalization Strategy Protocol

/// A swappable strategy for blend mode normalization.
/// Similar to RenderHook but specialized for luminance/contrast compensation.
protocol NormalizationStrategy {
    /// Display name for UI/debugging
    var name: String { get }

    /// Per-layer opacity compensation (called before each blend operation)
    /// Return 1.0 to apply no compensation.
    func opacityForLayer(
        index: Int,
        totalLayers: Int,
        blendMode: String,
        analysis: BlendModeAnalysis
    ) -> CGFloat

    /// Post-composition normalization (called after all layers are blended)
    /// Return the image unchanged if no post-processing needed.
    func normalizeComposite(
        _ image: CIImage,
        analysis: BlendModeAnalysis
    ) -> CIImage
}

// Default implementations - strategies can override what they need
extension NormalizationStrategy {
    func opacityForLayer(
        index: Int,
        totalLayers: Int,
        blendMode: String,
        analysis: BlendModeAnalysis
    ) -> CGFloat {
        return 1.0  // No per-layer compensation by default
    }

    func normalizeComposite(_ image: CIImage, analysis: BlendModeAnalysis) -> CIImage {
        return image  // No post-processing by default
    }
}

// MARK: - Strategy Registry

/// Registry of available normalization strategies (like EffectRegistry)
final class NormalizationRegistry {
    static let shared = NormalizationRegistry()

    private init() {}

    /// All available strategies
    func allStrategies() -> [NormalizationStrategy] {
        [
            NoNormalization(),
            SqrtOpacityStrategy(),
            GammaPostStrategy(),
            SqrtPlusGammaStrategy(),
            // Future: SigmoidStrategy(), ACESStrategy(), etc.
        ]
    }

    /// Get strategy by name
    func strategy(named: String) -> NormalizationStrategy? {
        allStrategies().first { $0.name == named }
    }

    /// Auto-select best strategy based on blend mode analysis
    func autoSelect(for analysis: BlendModeAnalysis) -> NormalizationStrategy {
        // No compensation needed for simple composites
        if !analysis.needsCompensation {
            return NoNormalization()
        }

        // Default: sqrt opacity + light gamma correction
        return SqrtPlusGammaStrategy()
    }
}


// MARK: - Concrete Strategies

/// No normalization - pass through unchanged
struct NoNormalization: NormalizationStrategy {
    var name: String { "None" }
}

/// Per-layer sqrt(n) opacity compensation only
/// Good for preventing drift without changing the final look
struct SqrtOpacityStrategy: NormalizationStrategy {
    var name: String { "Sqrt Opacity" }

    func opacityForLayer(
        index: Int,
        totalLayers: Int,
        blendMode: String,
        analysis: BlendModeAnalysis
    ) -> CGFloat {
        guard index > 0, totalLayers > 1 else { return 1.0 }

        let family = BlendModeClassifier.family(for: blendMode)
        let n = CGFloat(totalLayers)

        switch family {
        case .lightening, .darkening:
            // sqrt(n) rule: 2→0.71, 3→0.58, 4→0.50, 5→0.45
            return 1.0 / sqrt(n)
        case .contrast:
            // Gentler for contrast modes
            return 1.0 / pow(n, 0.3)
        case .neutral:
            return 1.0
        }
    }
}

/// Post-composition gamma correction only
/// Good for correcting existing compositions without changing blend behavior
struct GammaPostStrategy: NormalizationStrategy {
    var name: String { "Gamma Post" }

    func normalizeComposite(_ image: CIImage, analysis: BlendModeAnalysis) -> CIImage {
        guard analysis.needsCompensation else { return image }

        let gamma: Double
        switch analysis.dominantFamily {
        case .lightening:
            // Screen blowout: apply gamma > 1 to pull highlights down
            gamma = 1.0 + 0.15 * Double(analysis.lighteningCount)
        case .darkening:
            // Multiply crush: apply gamma < 1 to lift shadows
            gamma = 1.0 / (1.0 + 0.15 * Double(analysis.darkeningCount))
        case .contrast, .neutral, nil:
            // Mixed or neutral: light S-curve via moderate gamma
            gamma = 1.0 + 0.1 * Double(analysis.layerCount - 2)
        }

        guard let filter = CIFilter(name: "CIGammaAdjust") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(gamma, forKey: "inputPower")
        return filter.outputImage ?? image
    }
}

/// Hybrid: sqrt opacity + light gamma safety net
/// The recommended default - prevents drift AND catches residual issues
struct SqrtPlusGammaStrategy: NormalizationStrategy {
    var name: String { "Balanced (Auto)" }

    private let sqrtStrategy = SqrtOpacityStrategy()
    private let gammaStrategy = GammaPostStrategy()

    func opacityForLayer(
        index: Int,
        totalLayers: Int,
        blendMode: String,
        analysis: BlendModeAnalysis
    ) -> CGFloat {
        sqrtStrategy.opacityForLayer(
            index: index,
            totalLayers: totalLayers,
            blendMode: blendMode,
            analysis: analysis
        )
    }

    func normalizeComposite(_ image: CIImage, analysis: BlendModeAnalysis) -> CIImage {
        // Apply lighter gamma correction since opacity already did most of the work
        guard analysis.needsCompensation else { return image }

        let gamma: Double
        switch analysis.dominantFamily {
        case .lightening:
            gamma = 1.0 + 0.08 * Double(analysis.lighteningCount)
        case .darkening:
            gamma = 1.0 / (1.0 + 0.08 * Double(analysis.darkeningCount))
        case .contrast, .neutral, nil:
            return image  // Opacity compensation sufficient for mixed
        }

        guard let filter = CIFilter(name: "CIGammaAdjust") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(gamma, forKey: "inputPower")
        return filter.outputImage ?? image
    }
}

