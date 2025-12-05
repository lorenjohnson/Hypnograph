//
//  LuminanceRemovalHook.swift
//  Hypnograph
//
//  Makes pixels transparent based on luminance thresholds
//  Can remove dark pixels, light pixels, or a band in between
//

import CoreImage
import CoreMedia
import CoreGraphics

/// Removes pixels based on luminance, making them transparent
/// Used to punch holes in layers based on brightness
struct LuminanceRemovalHook: RenderHook {
    var name: String { effectName }
    
    enum Mode {
        case removeDark      // Make dark pixels transparent
        case removeLight     // Make light pixels transparent
        case removeMid       // Make mid-tone pixels transparent
    }
    
    private let effectName: String
    let mode: Mode
    
    /// Threshold for removal (0.0 to 1.0)
    /// For removeDark: pixels below this become transparent
    /// For removeLight: pixels above this become transparent
    /// For removeMid: pixels between lowThreshold and highThreshold become transparent
    let threshold: Float
    
    /// Secondary threshold for mid-tone removal
    let highThreshold: Float
    
    /// How soft the edge is (0.0 = hard cutoff, 1.0 = very gradual)
    let softness: Float
    
    init(mode: Mode, threshold: Float = 0.3, highThreshold: Float = 0.7, softness: Float = 0.1) {
        self.mode = mode
        self.threshold = threshold
        self.highThreshold = highThreshold
        self.softness = softness
        
        switch mode {
        case .removeDark: self.effectName = "Dark Removal"
        case .removeLight: self.effectName = "Light Removal"
        case .removeMid: self.effectName = "Mid Removal"
        }
    }
    
    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        // Use CIColorMatrix to create a luminance-based alpha mask
        // Then apply that mask to make pixels transparent
        
        // First, create a grayscale version to get luminance
        guard let grayscale = CIFilter(name: "CIPhotoEffectMono") else {
            return image
        }
        grayscale.setValue(image, forKey: kCIInputImageKey)
        
        guard let luminanceImage = grayscale.outputImage else {
            return image
        }
        
        // Create alpha mask based on mode
        // We'll use CIColorClamp and CIColorMatrix to threshold
        guard let colorMatrix = CIFilter(name: "CIColorMatrix") else {
            return image
        }
        
        // Calculate alpha based on luminance and mode
        // Using a kernel would be ideal, but we can approximate with filters
        
        let soft = CGFloat(max(0.01, softness))
        let thresh = CGFloat(threshold)
        let highThresh = CGFloat(highThreshold)
        
        // Use exposure adjustment to shift the luminance values
        guard let exposure = CIFilter(name: "CIExposureAdjust") else {
            return image
        }
        
        // Create the mask by manipulating the luminance image
        var maskImage = luminanceImage
        
        switch mode {
        case .removeDark:
            // Invert and threshold - dark areas become transparent
            // Shift so threshold becomes the midpoint
            exposure.setValue(maskImage, forKey: kCIInputImageKey)
            exposure.setValue(-2.0 * (1.0 - thresh), forKey: kCIInputEVKey)
            if let exposed = exposure.outputImage {
                maskImage = exposed
            }
            
        case .removeLight:
            // Light areas become transparent
            // Invert the luminance first
            if let invert = CIFilter(name: "CIColorInvert") {
                invert.setValue(maskImage, forKey: kCIInputImageKey)
                if let inverted = invert.outputImage {
                    maskImage = inverted
                    exposure.setValue(maskImage, forKey: kCIInputImageKey)
                    exposure.setValue(-2.0 * thresh, forKey: kCIInputEVKey)
                    if let exposed = exposure.outputImage {
                        maskImage = exposed
                    }
                }
            }
            
        case .removeMid:
            // Mid tones become transparent - use difference from edges
            guard let clamp = CIFilter(name: "CIColorClamp") else { break }
            clamp.setValue(maskImage, forKey: kCIInputImageKey)
            clamp.setValue(CIVector(x: thresh, y: thresh, z: thresh, w: 0), forKey: "inputMinComponents")
            clamp.setValue(CIVector(x: highThresh, y: highThresh, z: highThresh, w: 1), forKey: "inputMaxComponents")
            if let clamped = clamp.outputImage {
                // Now invert so the clamped (mid) area becomes dark
                if let invert = CIFilter(name: "CIColorInvert") {
                    invert.setValue(clamped, forKey: kCIInputImageKey)
                    if let inverted = invert.outputImage {
                        maskImage = inverted
                    }
                }
            }
        }
        
        // Apply gaussian blur for softness
        if softness > 0.05 {
            if let blur = CIFilter(name: "CIGaussianBlur") {
                blur.setValue(maskImage, forKey: kCIInputImageKey)
                blur.setValue(soft * 20.0, forKey: kCIInputRadiusKey)
                if let blurred = blur.outputImage {
                    maskImage = blurred.cropped(to: image.extent)
                }
            }
        }
        
        // Use the mask as alpha channel
        guard let maskToAlpha = CIFilter(name: "CIMaskToAlpha") else {
            return image
        }
        maskToAlpha.setValue(maskImage, forKey: kCIInputImageKey)
        
        guard let alphaMask = maskToAlpha.outputImage else {
            return image
        }
        
        // Blend original image with alpha mask
        guard let blend = CIFilter(name: "CIBlendWithAlphaMask") else {
            return image
        }
        
        blend.setValue(image, forKey: kCIInputImageKey)
        blend.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        blend.setValue(alphaMask, forKey: kCIInputMaskImageKey)
        
        if let result = blend.outputImage {
            return result.cropped(to: CGRect(origin: .zero, size: context.outputSize))
        }
        
        return image
    }
}

