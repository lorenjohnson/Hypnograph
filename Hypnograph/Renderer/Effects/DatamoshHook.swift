//
//  DatamoshHook.swift
//  Hypnograph
//
//  Created by Loren Johnson on 20.11.25.
//

import CoreImage
import CoreMedia
import CoreGraphics

/// EXTREME Datamosh effect - melty, drippy, chaotic frame smearing
/// Randomly holds onto old frames for extended periods creating liquid motion trails
struct DatamoshHook: RenderHook {
    var name: String { "Datamosh" }

    /// Intensity of the effect (0.0 = subtle, 1.0 = extreme)
    let intensity: Float

    init(intensity: Float = 0.9) {
        self.intensity = intensity
    }

    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        guard context.frameBuffer.isFilled else {
            return image
        }

        let t = CMTimeGetSeconds(context.time)
        let availableFrames = context.frameBuffer.frameCount

        // Create chaotic, random smearing patterns
        // Use multiple overlapping sine waves for unpredictable behavior
        let wave1 = sin(t * 0.3)
        let wave2 = sin(t * 0.17 + 2.5)
        let wave3 = sin(t * 0.41 + 5.0)
        let chaos = (wave1 + wave2 + wave3) / 3.0

        // Randomly choose very old frames (creates long smears)
        let seed = Int(t * 10.0) // Changes every 0.1 seconds
        let randomOffset = (seed * 7919) % max(1, availableFrames - 1) // Prime number for better distribution
        let offset = max(1, min(randomOffset, availableFrames - 1))

        guard let oldFrame = context.frameBuffer.previousFrame(offset: offset) else {
            return image
        }

        // Blend current with random old frame - creates melty trails
        // Higher chaos = more old frame showing through
        let blendAmount = CGFloat(abs(chaos) * CGFloat(intensity))

        guard let blendFilter = CIFilter(name: "CISourceOverCompositing") else {
            return image
        }

        // Create a semi-transparent version of the old frame
        guard let colorMatrix = CIFilter(name: "CIColorMatrix") else {
            return image
        }

        colorMatrix.setValue(oldFrame, forKey: kCIInputImageKey)
        colorMatrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        colorMatrix.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: blendAmount), forKey: "inputAVector")

        guard let transparentOld = colorMatrix.outputImage else {
            return image
        }

        blendFilter.setValue(transparentOld, forKey: kCIInputImageKey)
        blendFilter.setValue(image, forKey: kCIInputBackgroundImageKey)

        guard var result = blendFilter.outputImage else {
            return image
        }

        // Add displacement for extra meltiness
        if chaos > 0.3 {
            guard let displace = CIFilter(name: "CIDisplacementDistortion") else {
                return result
            }

            // Use difference between frames as displacement map
            guard let diff = CIFilter(name: "CIDifferenceBlendMode") else {
                return result
            }
            diff.setValue(image, forKey: kCIInputImageKey)
            diff.setValue(oldFrame, forKey: kCIInputBackgroundImageKey)

            if let diffImage = diff.outputImage {
                displace.setValue(result, forKey: kCIInputImageKey)
                displace.setValue(diffImage, forKey: "inputDisplacementImage")
                displace.setValue(50.0 * CGFloat(intensity) * abs(chaos), forKey: kCIInputScaleKey)

                if let displaced = displace.outputImage {
                    result = displaced
                }
            }
        }

        return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
    }

}
