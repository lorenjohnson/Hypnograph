//
//  BlackAndWhiteLowHook.swift
//  Hypnograph
//
//  Simple monochrome/contrast pass.
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Desaturate + slight contrast bump for a crisp black & white look.
struct BlackAndWhiteLowHook: RenderHook {
    var name: String { "Black & White - Low Contrast" }

    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        filter.setValue(0.7, forKey: kCIInputContrastKey)
        return filter.outputImage ?? image
    }
}
