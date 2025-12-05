//
//  SolarizeGlitchHook.swift
//  Hypnograph
//
//  Animated solarization with temporal variation
//  Inverts tones based on brightness threshold that changes over time
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Solarize glitch - animated solarization with temporal smearing
/// Threshold oscillates creating shifting inversions
struct SolarizeGlitchHook: RenderHook {
    var name: String { "Solarize Glitch" }
    
    /// Base intensity of the effect
    let intensity: Float
    
    /// How fast the threshold oscillates
    let speed: Double
    
    init(intensity: Float = 0.7, speed: Double = 0.3) {
        self.intensity = intensity
        self.speed = speed
    }
    
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        let t = CMTimeGetSeconds(context.time)
        
        // Oscillating threshold creates animated solarization
        let wave = sin(t * speed) * 0.5 + 0.5 // 0 to 1
        
        guard let solarize = CIFilter(name: "CIColorControls") else {
            return image
        }
        
        // Use extreme contrast as pseudo-solarization
        // Combined with previous frame blending
        solarize.setValue(image, forKey: kCIInputImageKey)
        solarize.setValue(1.0 + CGFloat(intensity) * CGFloat(wave), forKey: kCIInputContrastKey)
        solarize.setValue(CGFloat(wave * 0.5 - 0.25), forKey: kCIInputBrightnessKey)
        
        guard var result = solarize.outputImage else {
            return image
        }
        
        // Invert based on threshold for true solarize effect
        if let invert = CIFilter(name: "CIColorInvert") {
            invert.setValue(result, forKey: kCIInputImageKey)
            if let inverted = invert.outputImage {
                // Blend inverted with original based on wave
                guard let blend = CIFilter(name: "CISourceOverCompositing"),
                      let alpha = CIFilter(name: "CIColorMatrix") else {
                    return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
                }
                
                alpha.setValue(inverted, forKey: kCIInputImageKey)
                alpha.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                alpha.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
                alpha.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
                alpha.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(wave * CGFloat(intensity))), forKey: "inputAVector")
                
                if let transparentInvert = alpha.outputImage {
                    blend.setValue(transparentInvert, forKey: kCIInputImageKey)
                    blend.setValue(result, forKey: kCIInputBackgroundImageKey)
                    
                    if let blended = blend.outputImage {
                        result = blended
                    }
                }
            }
        }
        
        // Blend with previous frame for smearing
        if let prevFrame = context.frameBuffer.previousFrame(offset: 1) {
            guard let screen = CIFilter(name: "CIScreenBlendMode") else {
                return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
            }
            
            screen.setValue(prevFrame, forKey: kCIInputImageKey)
            screen.setValue(result, forKey: kCIInputBackgroundImageKey)
            
            if let screened = screen.outputImage {
                // Mix based on intensity
                guard let mix = CIFilter(name: "CISourceOverCompositing"),
                      let mixAlpha = CIFilter(name: "CIColorMatrix") else {
                    return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
                }
                
                mixAlpha.setValue(screened, forKey: kCIInputImageKey)
                mixAlpha.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                mixAlpha.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
                mixAlpha.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
                mixAlpha.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(intensity) * 0.3), forKey: "inputAVector")
                
                if let transparentScreen = mixAlpha.outputImage {
                    mix.setValue(transparentScreen, forKey: kCIInputImageKey)
                    mix.setValue(result, forKey: kCIInputBackgroundImageKey)
                    
                    if let mixed = mix.outputImage {
                        result = mixed
                    }
                }
            }
        }
        
        return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
    }
}

