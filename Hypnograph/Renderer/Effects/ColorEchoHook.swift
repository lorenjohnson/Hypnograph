//
//  ColorEchoHook.swift
//  Hypnograph
//
//  Echoes color channels from different points in time
//  Creates psychedelic RGB time-offset trails
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Color echo - each color channel comes from a different point in time
/// Red from now, green from N frames ago, blue from 2N frames ago
/// Uses max blend instead of additive to prevent white blowout
struct ColorEchoHook: RenderHook {
    var name: String { "Color Echo" }

    /// Needs 2x channel offset frames (blue channel is furthest back)
    var requiredLookback: Int { channelOffset * 2 + 1 }

    /// Frame offset between channels
    let channelOffset: Int

    init(channelOffset: Int = 2) {
        self.channelOffset = channelOffset
    }

    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        // Work with whatever frames are available (preroll fills buffer from frame 1)
        let maxOffset = max(0, context.frameBuffer.frameCount - 1)
        guard maxOffset >= 1 else { return image }  // Need at least 1 frame of history

        let greenOffset = min(channelOffset, maxOffset)
        let blueOffset = min(channelOffset * 2, maxOffset)

        guard let greenFrame = context.frameBuffer.previousFrame(offset: greenOffset),
              let blueFrame = context.frameBuffer.previousFrame(offset: blueOffset) else {
            return image
        }

        // Extract red from current frame (zero out G and B)
        guard let redFilter = CIFilter(name: "CIColorMatrix") else {
            return image
        }
        redFilter.setValue(image, forKey: kCIInputImageKey)
        redFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        redFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        redFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        redFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")

        // Extract green from offset frame (zero out R and B)
        guard let greenFilter = CIFilter(name: "CIColorMatrix") else {
            return image
        }
        greenFilter.setValue(greenFrame, forKey: kCIInputImageKey)
        greenFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        greenFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        greenFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        greenFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")

        // Extract blue from further offset frame (zero out R and G)
        guard let blueFilter = CIFilter(name: "CIColorMatrix") else {
            return image
        }
        blueFilter.setValue(blueFrame, forKey: kCIInputImageKey)
        blueFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        blueFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        blueFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        blueFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")

        guard let red = redFilter.outputImage,
              let green = greenFilter.outputImage,
              let blue = blueFilter.outputImage else {
            return image
        }

        // Combine using lighten blend (max per channel) - prevents white blowout
        // Since each image only has one non-zero channel, lighten picks that channel's value
        guard let blend1 = CIFilter(name: "CILightenBlendMode"),
              let blend2 = CIFilter(name: "CILightenBlendMode") else {
            return image
        }

        blend1.setValue(red, forKey: kCIInputImageKey)
        blend1.setValue(green, forKey: kCIInputBackgroundImageKey)

        guard let rg = blend1.outputImage else {
            return image
        }

        blend2.setValue(rg, forKey: kCIInputImageKey)
        blend2.setValue(blue, forKey: kCIInputBackgroundImageKey)

        guard let result = blend2.outputImage else {
            return image
        }

        return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
    }
}

