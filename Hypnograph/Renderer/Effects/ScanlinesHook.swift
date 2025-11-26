//
//  ScanlinesHook.swift
//  Hypnograph
//
//  Horizontal scanline glitch effect with irregular, organic variation
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Creates horizontal scanlines with irregular spacing and soft edges for a more organic CRT/VHS look
struct ScanlinesHook: RenderHook {
    var name: String { "Scanlines" }

    /// Width of each scanline in pixels
    let lineWidth: Float

    /// How much to darken alternate lines (0.0 = no effect, 1.0 = black)
    let intensity: Float

    init(lineWidth: Float = 2.0, intensity: Float = 0.3) {
        self.lineWidth = lineWidth
        self.intensity = intensity
    }

    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        let extent = image.extent

        // Create base scanline pattern using CIStripesGenerator
        guard let stripesFilter = CIFilter(name: "CIStripesGenerator") else {
            return image
        }

        stripesFilter.setValue(CIVector(x: 0, y: 0), forKey: "inputCenter")
        stripesFilter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(intensity)), forKey: "inputColor0")
        stripesFilter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
        stripesFilter.setValue(CGFloat(lineWidth), forKey: "inputWidth")

        guard var stripes = stripesFilter.outputImage else {
            return image
        }

        // Rotate stripes to be horizontal
        stripes = stripes.transformed(by: CGAffineTransform(rotationAngle: .pi / 2))

        // Add noise to make scanlines irregular and unpredictable
        if let noiseFilter = CIFilter(name: "CIRandomGenerator") {
            if var noise = noiseFilter.outputImage {
                // Scale noise to create variation in scanline intensity
                if let colorMatrix = CIFilter(name: "CIColorMatrix") {
                    colorMatrix.setValue(noise, forKey: kCIInputImageKey)
                    // Reduce noise intensity for subtle variation
                    colorMatrix.setValue(CIVector(x: 0.3, y: 0, z: 0, w: 0), forKey: "inputRVector")
                    colorMatrix.setValue(CIVector(x: 0, y: 0.3, z: 0, w: 0), forKey: "inputGVector")
                    colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0.3, w: 0), forKey: "inputBVector")
                    colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")

                    if let scaledNoise = colorMatrix.outputImage {
                        noise = scaledNoise
                    }
                }

                // Blend noise with stripes to create irregular patterns
                if let multiplyFilter = CIFilter(name: "CIMultiplyBlendMode") {
                    multiplyFilter.setValue(noise.cropped(to: extent), forKey: kCIInputImageKey)
                    multiplyFilter.setValue(stripes, forKey: kCIInputBackgroundImageKey)

                    if let noisyStripes = multiplyFilter.outputImage {
                        stripes = noisyStripes
                    }
                }
            }
        }

        // Apply gaussian blur to soften edges and make lines less sharp
        if let blurFilter = CIFilter(name: "CIGaussianBlur") {
            blurFilter.setValue(stripes, forKey: kCIInputImageKey)
            blurFilter.setValue(1.5, forKey: kCIInputRadiusKey) // Subtle blur for soft edges

            if let blurred = blurFilter.outputImage {
                stripes = blurred
            }
        }

        // Crop to image extent
        stripes = stripes.cropped(to: extent)

        // Blend scanlines over the image using multiply blend mode
        guard let blendFilter = CIFilter(name: "CIMultiplyBlendMode") else {
            return image
        }

        blendFilter.setValue(stripes, forKey: kCIInputImageKey)
        blendFilter.setValue(image, forKey: kCIInputBackgroundImageKey)

        return blendFilter.outputImage ?? image
    }
}

