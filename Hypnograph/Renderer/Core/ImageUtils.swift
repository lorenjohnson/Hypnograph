//
//  ImageUtils.swift
//  Hypnograph
//
//  Shared image processing utilities used by FrameCompositor and FrameProcessor.
//  Centralized here to ensure consistent behavior across Montage and Sequence modes.
//

import CoreImage

enum ImageUtils {
    
    /// Scale and crop an image to fill the target size while maintaining aspect ratio.
    /// The image is centered, with overflow cropped equally from both sides.
    static func aspectFill(image: CIImage, to size: CGSize) -> CIImage {
        // First, translate image so its origin is at (0,0) if needed
        var img = image
        if img.extent.origin != .zero {
            img = img.transformed(by: CGAffineTransform(
                translationX: -img.extent.origin.x,
                y: -img.extent.origin.y
            ))
        }

        let imageSize = img.extent.size
        guard imageSize.width > 0, imageSize.height > 0, size.width > 0, size.height > 0 else {
            return img
        }

        let scale = max(size.width / imageSize.width, size.height / imageSize.height)

        let scaledImage = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledSize = scaledImage.extent.size

        let x = (size.width - scaledSize.width) / 2
        let y = (size.height - scaledSize.height) / 2

        let translated = scaledImage.transformed(by: CGAffineTransform(translationX: x, y: y))

        return translated.cropped(to: CGRect(origin: .zero, size: size))
    }
    
    /// Blend a foreground layer over a background using a Core Image blend filter.
    static func blend(layer: CIImage, over base: CIImage, mode: String) -> CIImage {
        let filter = CIFilter(name: mode)
        filter?.setValue(layer, forKey: kCIInputImageKey)
        filter?.setValue(base, forKey: kCIInputBackgroundImageKey)
        return filter?.outputImage ?? layer
    }
}

