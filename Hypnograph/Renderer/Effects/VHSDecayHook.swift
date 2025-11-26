//
//  VHSDecayHook.swift
//  Hypnograph
//
//  VHS tape decay effect - tracking errors, color bleeding, noise, and degradation
//

import CoreImage
import CoreMedia
import CoreGraphics

/// VHS tape decay - simulates degraded VHS playback with tracking errors and noise
struct VHSDecayHook: RenderHook {
    var name: String { "VHS Decay" }
    
    let intensity: Float
    
    init(intensity: Float = 0.7) {
        self.intensity = intensity
    }
    
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        let t = CMTimeGetSeconds(context.time)
        var result = image
        
        // 1. Horizontal tracking errors (random line shifts)
        let trackingGlitch = sin(t * 5.0 + sin(t * 13.0)) // Chaotic oscillation
        if abs(trackingGlitch) > 0.7 {
            // Shift image horizontally
            let shift = CGFloat(trackingGlitch * 50.0 * CGFloat(intensity))
            result = result.transformed(by: CGAffineTransform(translationX: shift, y: 0))
        }
        
        // 2. Color channel separation (chromatic aberration)
        // Shift red channel
        let redShift = result.transformed(by: CGAffineTransform(translationX: 3.0 * CGFloat(intensity), y: 0))
        
        // Shift blue channel
        let blueShift = result.transformed(by: CGAffineTransform(translationX: -3.0 * CGFloat(intensity), y: 0))
        
        // Recombine channels
        guard let redFilter = CIFilter(name: "CIColorMatrix") else {
            return result
        }
        redFilter.setValue(redShift, forKey: kCIInputImageKey)
        redFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        redFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        redFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        
        guard let blueFilter = CIFilter(name: "CIColorMatrix") else {
            return result
        }
        blueFilter.setValue(blueShift, forKey: kCIInputImageKey)
        blueFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        blueFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        blueFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        
        guard let greenFilter = CIFilter(name: "CIColorMatrix") else {
            return result
        }
        greenFilter.setValue(result, forKey: kCIInputImageKey)
        greenFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        greenFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        greenFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        
        // Blend channels back together
        if let red = redFilter.outputImage,
           let green = greenFilter.outputImage,
           let blue = blueFilter.outputImage,
           let addFilter = CIFilter(name: "CIAdditionCompositing") {
            
            addFilter.setValue(red, forKey: kCIInputImageKey)
            addFilter.setValue(green, forKey: kCIInputBackgroundImageKey)
            
            if let rg = addFilter.outputImage {
                addFilter.setValue(blue, forKey: kCIInputImageKey)
                addFilter.setValue(rg, forKey: kCIInputBackgroundImageKey)
                
                if let rgb = addFilter.outputImage {
                    result = rgb
                }
            }
        }
        
        // 3. Add noise (tape grain)
        guard let noise = CIFilter(name: "CIRandomGenerator") else {
            return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
        }
        
        guard let noiseImage = noise.outputImage else {
            return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
        }
        
        // Scale and crop noise to match image size
        let scaledNoise = noiseImage.transformed(by: CGAffineTransform(scaleX: 3, y: 3))
            .cropped(to: CGRect(origin: .zero, size: context.outputSize))
        
        // Blend noise with image
        guard let noiseBlend = CIFilter(name: "CISourceOverCompositing") else {
            return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
        }
        
        // Make noise semi-transparent
        guard let noiseAlpha = CIFilter(name: "CIColorMatrix") else {
            return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
        }
        
        noiseAlpha.setValue(scaledNoise, forKey: kCIInputImageKey)
        noiseAlpha.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputAVector")
        noiseAlpha.setValue(CIVector(x: 0, y: 0, z: 0, w: 0.1 * CGFloat(intensity)), forKey: "inputBiasVector")
        
        if let transparentNoise = noiseAlpha.outputImage {
            noiseBlend.setValue(transparentNoise, forKey: kCIInputImageKey)
            noiseBlend.setValue(result, forKey: kCIInputBackgroundImageKey)
            
            if let noisyResult = noiseBlend.outputImage {
                result = noisyResult
            }
        }
        
        // 4. Reduce saturation slightly (VHS color degradation)
        guard let colorControls = CIFilter(name: "CIColorControls") else {
            return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
        }
        
        colorControls.setValue(result, forKey: kCIInputImageKey)
        colorControls.setValue(0.7, forKey: kCIInputSaturationKey)
        colorControls.setValue(1.1, forKey: kCIInputContrastKey)
        
        if let final = colorControls.outputImage {
            result = final
        }
        
        return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
    }
}

