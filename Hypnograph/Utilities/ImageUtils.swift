//
//  ImageUtils.swift
//  Hypnograph
//
//  Shared image processing utilities used by app-level image pipelines.
//  Centralized here to keep MetalImageView/FrameProcessor behavior consistent.
//

import CoreImage

enum ImageUtils {

    /// Convert AVFoundation's preferredTransform to work correctly with CIImage.
    ///
    /// AVFoundation's preferredTransform assumes a top-left origin coordinate system,
    /// but CIImage uses bottom-left origin. To convert, we conjugate by a y-flip:
    /// T' = S * T * S where S = scale(1, -1).
    ///
    /// This gives: a' = a, b' = -b, c' = -c, d' = d, tx' = tx, ty' = -ty
    static func convertTransformForCIImage(_ transform: CGAffineTransform, naturalSize: CGSize) -> CGAffineTransform {
        // If identity, no conversion needed
        if transform.isIdentity {
            return transform
        }

        // Conjugate by y-flip: negate b, c, and ty
        return CGAffineTransform(
            a: transform.a,
            b: -transform.b,
            c: -transform.c,
            d: transform.d,
            tx: transform.tx,
            ty: -transform.ty
        )
    }

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
    /// - Parameters:
    ///   - layer: The foreground image to blend
    ///   - base: The background image
    ///   - mode: CI blend filter name (e.g., "CIScreenBlendMode")
    ///   - opacity: Optional opacity multiplier (0-1). If < 1, blends result with base.
    static func blend(
        layer: CIImage,
        over base: CIImage,
        mode: String,
        opacity: CGFloat = 1.0
    ) -> CIImage {
        let filter = CIFilter(name: mode)
        filter?.setValue(layer, forKey: kCIInputImageKey)
        filter?.setValue(base, forKey: kCIInputBackgroundImageKey)

        guard let blended = filter?.outputImage else { return layer }

        // If full opacity, return blended result directly
        guard opacity < 1.0 else { return blended }

        // Partial opacity: lerp between base and blended result
        // result = base * (1 - opacity) + blended * opacity
        return applyOpacity(blended, over: base, opacity: opacity)
    }

    /// Apply opacity by blending foreground over background
    /// result = background * (1 - opacity) + foreground * opacity
    private static func applyOpacity(
        _ foreground: CIImage,
        over background: CIImage,
        opacity: CGFloat
    ) -> CIImage {
        // Use CIColorMatrix to apply opacity to the foreground
        guard let opacityFilter = CIFilter(name: "CIColorMatrix") else {
            return foreground
        }

        // Alpha vector: multiply alpha channel by opacity
        let alphaVector = CIVector(x: 0, y: 0, z: 0, w: opacity)
        opacityFilter.setValue(foreground, forKey: kCIInputImageKey)
        opacityFilter.setValue(alphaVector, forKey: "inputAVector")

        guard let transparentForeground = opacityFilter.outputImage else {
            return foreground
        }

        // Composite over background
        guard let composite = CIFilter(name: "CISourceOverCompositing") else {
            return foreground
        }
        composite.setValue(transparentForeground, forKey: kCIInputImageKey)
        composite.setValue(background, forKey: kCIInputBackgroundImageKey)

        return composite.outputImage ?? foreground
    }
}
