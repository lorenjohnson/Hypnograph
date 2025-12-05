//
//  ColorEchoHook.swift
//  Hypnograph
//
//  Echoes color channels from different points in time
//  Creates psychedelic RGB time-offset trails
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Color echo - each color channel comes from a different point in time
/// Red from now, green from 2 frames ago, blue from 4 frames ago
struct ColorEchoHook: RenderHook {
    var name: String { "Color Echo" }
    
    /// Frame offset between channels
    let channelOffset: Int
    
    init(channelOffset: Int = 2) {
        self.channelOffset = channelOffset
    }
    
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        guard context.frameBuffer.isFilled else {
            return image
        }
        
        let maxOffset = context.frameBuffer.frameCount - 1
        let greenOffset = min(channelOffset, maxOffset)
        let blueOffset = min(channelOffset * 2, maxOffset)
        
        guard let greenFrame = context.frameBuffer.previousFrame(offset: greenOffset),
              let blueFrame = context.frameBuffer.previousFrame(offset: blueOffset) else {
            return image
        }
        
        // Extract red from current frame
        guard let redFilter = CIFilter(name: "CIColorMatrix") else {
            return image
        }
        redFilter.setValue(image, forKey: kCIInputImageKey)
        redFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        redFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        redFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        redFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        
        // Extract green from offset frame
        guard let greenFilter = CIFilter(name: "CIColorMatrix") else {
            return image
        }
        greenFilter.setValue(greenFrame, forKey: kCIInputImageKey)
        greenFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        greenFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        greenFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        greenFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        
        // Extract blue from further offset frame
        guard let blueFilter = CIFilter(name: "CIColorMatrix") else {
            return image
        }
        blueFilter.setValue(blueFrame, forKey: kCIInputImageKey)
        blueFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        blueFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        blueFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        blueFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        
        guard let red = redFilter.outputImage,
              let green = greenFilter.outputImage,
              let blue = blueFilter.outputImage else {
            return image
        }
        
        // Combine channels using additive blending
        guard let add1 = CIFilter(name: "CIAdditionCompositing"),
              let add2 = CIFilter(name: "CIAdditionCompositing") else {
            return image
        }
        
        add1.setValue(red, forKey: kCIInputImageKey)
        add1.setValue(green, forKey: kCIInputBackgroundImageKey)
        
        guard let rg = add1.outputImage else {
            return image
        }
        
        add2.setValue(rg, forKey: kCIInputImageKey)
        add2.setValue(blue, forKey: kCIInputBackgroundImageKey)
        
        guard let result = add2.outputImage else {
            return image
        }
        
        return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
    }
}

