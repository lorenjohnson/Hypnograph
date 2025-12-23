//
//  MirrorKaleidoHook.swift
//  Hypnograph
//
//  Kaleidoscope mirror effect - creates symmetrical patterns by reflecting image segments
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Kaleidoscope effect - mirrors and rotates image to create symmetrical patterns
struct MirrorKaleidoHook: RenderHook {

    // MARK: - Parameter Specs (source of truth)

    static var parameterSpecs: [String: ParameterSpec] {
        [
            "intensity": .float(default: 0.8, range: 0...1)
        ]
    }

    // MARK: - Properties

    var name: String { "Kaleidoscope" }

    let intensity: Float

    init(intensity: Float = 0.8) {
        self.intensity = intensity
    }

    init?(params: [String: AnyCodableValue]?) {
        let intensity = params?["intensity"]?.floatValue ?? 0.8
        self.init(intensity: intensity)
    }
    
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        let t = CMTimeGetSeconds(context.time)

        // Rotation speed
        let rotation = t * 0.5
        
        // Use triangle kaleidoscope filter
        guard let kaleido = CIFilter(name: "CITriangleKaleidoscope") else {
            return image
        }
        
        // Center point (oscillates slightly for movement)
        let centerX = context.outputSize.width / 2.0 + 50.0 * sin(t * 0.4)
        let centerY = context.outputSize.height / 2.0 + 50.0 * cos(t * 0.3)
        
        kaleido.setValue(image, forKey: kCIInputImageKey)
        kaleido.setValue(CIVector(x: centerX, y: centerY), forKey: "inputPoint")
        kaleido.setValue(200.0 * CGFloat(intensity), forKey: "inputSize")
        kaleido.setValue(rotation, forKey: "inputRotation")
        kaleido.setValue(CGFloat(intensity), forKey: "inputDecay")
        
        guard var result = kaleido.outputImage else {
            return image
        }
        
        // Blend with original image based on intensity
        guard let blend = CIFilter(name: "CISourceOverCompositing") else {
            return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
        }
        
        // Make kaleidoscope semi-transparent
        guard let alpha = CIFilter(name: "CIColorMatrix") else {
            return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
        }
        
        alpha.setValue(result, forKey: kCIInputImageKey)
        alpha.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        alpha.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        alpha.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        alpha.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(intensity)), forKey: "inputAVector")
        
        if let transparentKaleido = alpha.outputImage {
            blend.setValue(transparentKaleido, forKey: kCIInputImageKey)
            blend.setValue(image, forKey: kCIInputBackgroundImageKey)
            
            if let blended = blend.outputImage {
                result = blended
            }
        }
        
        return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
    }
}

