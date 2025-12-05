//
//  FrameDifferenceHook.swift
//  Hypnograph
//
//  Shows only the difference between frames - reveals motion as bright areas
//  Static areas become dark/transparent
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Frame difference effect - highlights motion by showing inter-frame differences
/// Great for creating ghostly motion trails on dark backgrounds
struct FrameDifferenceHook: RenderHook {
    var name: String { "Frame Difference" }
    
    /// How much original image to blend back (0.0 = pure difference, 1.0 = mostly original)
    let originalBlend: Float
    
    /// Boost the difference signal
    let boost: Float
    
    init(originalBlend: Float = 0.3, boost: Float = 2.0) {
        self.originalBlend = originalBlend
        self.boost = boost
    }
    
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        guard let prevFrame = context.frameBuffer.previousFrame(offset: 1) else {
            return image
        }
        
        // Compute absolute difference between current and previous frame
        guard let diffFilter = CIFilter(name: "CIDifferenceBlendMode") else {
            return image
        }
        
        diffFilter.setValue(image, forKey: kCIInputImageKey)
        diffFilter.setValue(prevFrame, forKey: kCIInputBackgroundImageKey)
        
        guard var difference = diffFilter.outputImage else {
            return image
        }
        
        // Boost the difference
        if boost > 1.0 {
            if let exposure = CIFilter(name: "CIExposureAdjust") {
                exposure.setValue(difference, forKey: kCIInputImageKey)
                exposure.setValue(Double(boost), forKey: kCIInputEVKey)
                if let boosted = exposure.outputImage {
                    difference = boosted
                }
            }
        }
        
        // Blend back some original
        if originalBlend > 0.01 {
            guard let blend = CIFilter(name: "CISourceOverCompositing"),
                  let alpha = CIFilter(name: "CIColorMatrix") else {
                return difference.cropped(to: CGRect(origin: .zero, size: context.outputSize))
            }
            
            alpha.setValue(image, forKey: kCIInputImageKey)
            alpha.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
            alpha.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
            alpha.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
            alpha.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(originalBlend)), forKey: "inputAVector")
            
            if let transparentOriginal = alpha.outputImage {
                blend.setValue(transparentOriginal, forKey: kCIInputImageKey)
                blend.setValue(difference, forKey: kCIInputBackgroundImageKey)
                if let blended = blend.outputImage {
                    return blended.cropped(to: CGRect(origin: .zero, size: context.outputSize))
                }
            }
        }
        
        return difference.cropped(to: CGRect(origin: .zero, size: context.outputSize))
    }
}

