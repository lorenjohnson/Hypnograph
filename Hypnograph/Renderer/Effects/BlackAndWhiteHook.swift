//
//  BlackAndWhiteHook.swift
//  Hypnograph
//
//  Simple monochrome/contrast pass with configurable contrast.
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Desaturate + configurable contrast for black & white look.
struct BlackAndWhiteHook: RenderHook {

    // MARK: - Parameter Specs (source of truth)

    static var parameterSpecs: [String: ParameterSpec] {
        [
            "contrast": .float(default: 1.0, range: 0...10)
        ]
    }

    // MARK: - Properties

    /// Contrast level (1.0 = normal, <1 = low contrast, >1 = high contrast)
    let contrast: Float

    /// Display name includes contrast level
    var name: String {
        if contrast != 1.0 {
            return "B&W - Contrast \(contrast)"
        } else {
            return "B&W"
        }
    }

    init(contrast: Float = 1.0) {
        self.contrast = contrast
    }

    init?(params: [String: AnyCodableValue]?) {
        let contrast = params?["contrast"]?.floatValue ?? 1.0
        self.init(contrast: contrast)
    }

    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        filter.setValue(contrast, forKey: kCIInputContrastKey)
        return filter.outputImage ?? image
    }
}

// MARK: - Backwards compatibility aliases
typealias BlackAndWhiteHighHook = BlackAndWhiteHook
typealias BlackAndWhiteLowHook = BlackAndWhiteHook
