//
//  DatamoshHook3.swift
//  Hypnograph
//
//  Deep, smeary datamosh - motion-aware frame bleeding without color shifts
//  Accumulates motion over time creating viscous, liquid-like trails
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Deep datamosh effect - persistent smeary motion trails
/// Uses motion detection between frames to create organic, flowing distortion
/// Avoids color shifts, focuses on displacement and blending
struct DatamoshHook3: RenderHook {
    var name: String { "Datamosh3" }
    
    /// How much frames bleed together (0.0 = minimal, 1.0 = extreme)
    let intensity: Float
    
    /// How many frames back to look for motion accumulation
    let historyDepth: Int
    
    init(intensity: Float = 0.6, historyDepth: Int = 8) {
        self.intensity = intensity
        self.historyDepth = historyDepth
    }
    
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        guard context.frameBuffer.isFilled else {
            return image
        }
        
        let availableFrames = min(historyDepth, context.frameBuffer.frameCount - 1)
        guard availableFrames >= 2 else { return image }
        
        var result = image
        
        // Get multiple previous frames for motion analysis
        guard let prev1 = context.frameBuffer.previousFrame(offset: 1),
              let prev2 = context.frameBuffer.previousFrame(offset: min(3, availableFrames)) else {
            return image
        }
        
        // Create motion vector by finding difference between frames
        // This gives us where motion is happening
        guard let diffFilter = CIFilter(name: "CIDifferenceBlendMode") else {
            return image
        }
        
        diffFilter.setValue(prev1, forKey: kCIInputImageKey)
        diffFilter.setValue(prev2, forKey: kCIInputBackgroundImageKey)
        
        guard let motionMap = diffFilter.outputImage else {
            return image
        }
        
        // Blur the motion map for smoother displacement
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return image
        }
        
        blurFilter.setValue(motionMap, forKey: kCIInputImageKey)
        blurFilter.setValue(12.0 * CGFloat(intensity), forKey: kCIInputRadiusKey)
        
        guard let blurredMotion = blurFilter.outputImage else {
            return image
        }
        
        // Use motion map to displace current frame - creates smearing where motion occurs
        guard let displaceFilter = CIFilter(name: "CIDisplacementDistortion") else {
            return image
        }
        
        displaceFilter.setValue(result, forKey: kCIInputImageKey)
        displaceFilter.setValue(blurredMotion, forKey: "inputDisplacementImage")
        displaceFilter.setValue(40.0 * CGFloat(intensity), forKey: kCIInputScaleKey)
        
        if let displaced = displaceFilter.outputImage {
            result = displaced
        }
        
        // Accumulate frames weighted by their motion contribution
        // Older frames with high motion get blended in
        for offset in 2...min(5, availableFrames) {
            guard let oldFrame = context.frameBuffer.previousFrame(offset: offset) else { continue }
            
            // Falloff: older frames contribute less
            let weight = CGFloat(1.0 - Float(offset) / Float(availableFrames + 1)) * CGFloat(intensity) * 0.3
            
            // Blend with luminosity to preserve colors
            guard let blendFilter = CIFilter(name: "CISoftLightBlendMode") else { continue }
            
            blendFilter.setValue(oldFrame, forKey: kCIInputImageKey)
            blendFilter.setValue(result, forKey: kCIInputBackgroundImageKey)
            
            if let blended = blendFilter.outputImage {
                // Mix original with blend
                guard let mixFilter = CIFilter(name: "CISourceOverCompositing"),
                      let alphaFilter = CIFilter(name: "CIColorMatrix") else { continue }
                
                alphaFilter.setValue(blended, forKey: kCIInputImageKey)
                alphaFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                alphaFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
                alphaFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
                alphaFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: weight), forKey: "inputAVector")
                
                if let transparent = alphaFilter.outputImage {
                    mixFilter.setValue(transparent, forKey: kCIInputImageKey)
                    mixFilter.setValue(result, forKey: kCIInputBackgroundImageKey)
                    
                    if let mixed = mixFilter.outputImage {
                        result = mixed
                    }
                }
            }
        }
        
        return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
    }
}

