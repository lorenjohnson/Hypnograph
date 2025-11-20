//
//  ScanlinesHook.swift
//  Hypnograph
//
//  Horizontal scanline glitch effect
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Creates horizontal scanlines for a retro CRT/VHS look
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
        
        // Create a scanline pattern using CIStripesGenerator
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

