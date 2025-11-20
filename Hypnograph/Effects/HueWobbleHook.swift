//
//  HueWobbleHook.swift
//  Hypnograph
//
//  Created by Loren Johnson on 20.11.25.
//

import CoreImage
import CoreMedia

/// Wobbles the hue over time with a sinusoidal oscillation.
struct HueWobbleHook: RenderHook {
    var name: String { "Hue Wobble" }
    
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        let t = CMTimeGetSeconds(context.time)
        let phase = Float(sin(t * 0.5))          // slow-ish oscillation
        let angle = phase * .pi                  // radians

        guard let filter = CIFilter(name: "CIHueAdjust") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(angle, forKey: kCIInputAngleKey)

        return filter.outputImage ?? image
    }
}

