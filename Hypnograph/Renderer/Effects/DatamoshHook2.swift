//
//  DatamoshHook2.swift
//  Hypnograph
//
//  Subtle, smeary datamosh - less flashy/stroby, more queasy and smooth
//  Focuses on slow, blurry ghosting rather than sharp displacement
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Subtle datamosh effect - slow, smeary, queasy frame ghosting
/// Creates smooth, blurred trails that linger and fade gradually
struct DatamoshHook2: RenderHook {
    var name: String { "Datamosh2" }

    /// Intensity controls how long frames linger (0.0 = brief, 1.0 = very long)
    let intensity: Float
    
    /// How much to blur the ghosted frames (higher = smoother, less mosaic-y)
    let blurAmount: CGFloat
    
    /// How slowly the effect changes (higher = slower, less spazzy)
    let timeScale: Double

    init(intensity: Float = 0.7, blurAmount: CGFloat = 8.0, timeScale: Double = 0.05) {
        self.intensity = intensity
        self.blurAmount = blurAmount
        self.timeScale = timeScale
    }

    init?(params: [String: AnyCodableValue]?) {
        let intensity = params?["intensity"]?.floatValue ?? 0.7
        let blurAmount = params?["blurAmount"]?.floatValue ?? 8.0
        let timeScale = params?["timeScale"]?.floatValue ?? 0.05
        self.init(intensity: intensity, blurAmount: CGFloat(blurAmount), timeScale: Double(timeScale))
    }

    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        guard context.frameBuffer.isFilled else {
            return image
        }

        let t = CMTimeGetSeconds(context.time)
        let availableFrames = context.frameBuffer.frameCount

        // MUCH slower oscillation - creates queasy, slow drift
        // Single slow sine wave instead of chaotic multi-wave
        let slowWave = sin(t * timeScale)
        
        // Map to frame offset - intensity controls how far back we reach
        // Higher intensity = longer smears
        let maxOffset = Int(Float(availableFrames - 1) * intensity)
        let normalizedWave = (slowWave + 1.0) / 2.0 // 0.0 to 1.0
        let offset = max(1, Int(normalizedWave * Double(maxOffset)))

        guard let oldFrame = context.frameBuffer.previousFrame(offset: offset) else {
            return image
        }

        // Apply gaussian blur to the old frame to make it smooth and dreamy
        // This prevents the mosaic/posterized look
        var blurredOld = oldFrame
        if blurAmount > 0 {
            if let blur = CIFilter(name: "CIGaussianBlur") {
                blur.setValue(oldFrame, forKey: kCIInputImageKey)
                blur.setValue(blurAmount, forKey: kCIInputRadiusKey)
                if let blurred = blur.outputImage {
                    blurredOld = blurred
                }
            }
        }

        // Gentle, consistent blend - no sudden flashes
        // Use a lower, more consistent opacity for smooth ghosting
        let baseOpacity = 0.3 + (0.4 * CGFloat(intensity)) // 0.3 to 0.7 range
        let blendAmount = baseOpacity * CGFloat(abs(slowWave) * 0.5 + 0.5) // Modulate gently

        // Create semi-transparent ghosted frame
        guard let colorMatrix = CIFilter(name: "CIColorMatrix") else {
            return image
        }

        colorMatrix.setValue(blurredOld, forKey: kCIInputImageKey)
        colorMatrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        colorMatrix.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: blendAmount), forKey: "inputAVector")

        guard let transparentOld = colorMatrix.outputImage else {
            return image
        }

        // Blend ghosted frame over current frame
        guard let blendFilter = CIFilter(name: "CISourceOverCompositing") else {
            return image
        }

        blendFilter.setValue(transparentOld, forKey: kCIInputImageKey)
        blendFilter.setValue(image, forKey: kCIInputBackgroundImageKey)

        guard var result = blendFilter.outputImage else {
            return image
        }

        // Optional: Very subtle displacement for slight smearing
        // Only apply occasionally and gently - no harsh distortion
        if abs(slowWave) > 0.7 && intensity > 0.5 {
            guard let displace = CIFilter(name: "CIDisplacementDistortion") else {
                return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
            }

            // Use blurred difference for smooth displacement
            guard let diff = CIFilter(name: "CIDifferenceBlendMode") else {
                return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
            }
            
            diff.setValue(image, forKey: kCIInputImageKey)
            diff.setValue(blurredOld, forKey: kCIInputBackgroundImageKey)

            if let diffImage = diff.outputImage {
                // Blur the displacement map too for smoother distortion
                var displacementMap = diffImage
                if let blurDisp = CIFilter(name: "CIGaussianBlur") {
                    blurDisp.setValue(diffImage, forKey: kCIInputImageKey)
                    blurDisp.setValue(blurAmount * 0.5, forKey: kCIInputRadiusKey)
                    if let blurred = blurDisp.outputImage {
                        displacementMap = blurred
                    }
                }
                
                displace.setValue(result, forKey: kCIInputImageKey)
                displace.setValue(displacementMap, forKey: "inputDisplacementImage")
                // Much gentler displacement scale
                displace.setValue(15.0 * CGFloat(intensity), forKey: kCIInputScaleKey)

                if let displaced = displace.outputImage {
                    result = displaced
                }
            }
        }

        return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
    }
}

