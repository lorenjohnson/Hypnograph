//
//  RGBSplitHook.swift
//  Hypnograph
//
//  RGB channel separation glitch effect
//

import CoreImage
import CoreMedia
import CoreGraphics

/// RGB channel separation effect using CoreImage filters
struct RGBSplitSimpleHook: RenderHook {
    var name: String { "RGB Split" }
    
    let offsetAmount: Float
    let animated: Bool
    
    init(offsetAmount: Float = 10.0, animated: Bool = true) {
        self.offsetAmount = offsetAmount
        self.animated = animated
    }
    
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        // Calculate offset (animate if enabled)
        var offset = CGFloat(offsetAmount)
        if animated {
            let t = CMTimeGetSeconds(context.time)
            // Oscillate the offset with some randomness
            let phase = sin(t * 2.0) * 0.5 + 0.5 // 0 to 1
            offset *= phase
        }
        
        let extent = image.extent
        
        // Extract individual color channels and shift them
        // Red channel - shift right
        let redTransform = CGAffineTransform(translationX: offset, y: 0)
        let redShifted = image.transformed(by: redTransform)
        
        // Blue channel - shift left
        let blueTransform = CGAffineTransform(translationX: -offset, y: 0)
        let blueShifted = image.transformed(by: blueTransform)
        
        // Use color matrix to extract channels
        guard let redFilter = CIFilter(name: "CIColorMatrix"),
              let blueFilter = CIFilter(name: "CIColorMatrix"),
              let greenFilter = CIFilter(name: "CIColorMatrix") else {
            return image
        }
        
        // Red channel only
        redFilter.setValue(redShifted, forKey: kCIInputImageKey)
        redFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        redFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        redFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        
        // Green channel only (no shift)
        greenFilter.setValue(image, forKey: kCIInputImageKey)
        greenFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        greenFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        greenFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        
        // Blue channel only
        blueFilter.setValue(blueShifted, forKey: kCIInputImageKey)
        blueFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        blueFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        blueFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        
        guard let red = redFilter.outputImage,
              let green = greenFilter.outputImage,
              let blue = blueFilter.outputImage else {
            return image
        }
        
        // Combine channels using addition
        guard let addFilter1 = CIFilter(name: "CIAdditionCompositing"),
              let addFilter2 = CIFilter(name: "CIAdditionCompositing") else {
            return image
        }
        
        // Add red + green
        addFilter1.setValue(red, forKey: kCIInputImageKey)
        addFilter1.setValue(green, forKey: kCIInputBackgroundImageKey)
        
        guard let rg = addFilter1.outputImage else {
            return image
        }
        
        // Add (red+green) + blue
        addFilter2.setValue(blue, forKey: kCIInputImageKey)
        addFilter2.setValue(rg, forKey: kCIInputBackgroundImageKey)
        
        return addFilter2.outputImage?.cropped(to: extent) ?? image
    }
}

