//
//  CompositionPreviewImageCodec.swift
//  Hypnograph
//

import Foundation
import AppKit
import CoreGraphics

struct CompositionPreviewImages {
    let snapshotBase64: String
    let thumbnailBase64: String
}

enum CompositionPreviewImageCodec {
    static let snapshotWidth: CGFloat = 1920
    static let snapshotHeight: CGFloat = 1080
    static let snapshotJPEGQuality: CGFloat = 0.85
    static let thumbnailSize: CGFloat = 120
    static let thumbnailJPEGQuality: CGFloat = 0.7

    static func makePreviewImages(from image: CGImage) -> CompositionPreviewImages? {
        guard
            let snapshotBase64 = encodeSnapshot(image),
            let thumbnailBase64 = encodeThumbnail(image)
        else {
            return nil
        }

        return CompositionPreviewImages(
            snapshotBase64: snapshotBase64,
            thumbnailBase64: thumbnailBase64
        )
    }

    static func encodeSnapshot(_ image: CGImage) -> String? {
        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)

        let widthRatio = snapshotWidth / sourceWidth
        let heightRatio = snapshotHeight / sourceHeight
        let scale = min(widthRatio, heightRatio, 1.0)

        let targetWidth = Int(sourceWidth * scale)
        let targetHeight = Int(sourceHeight * scale)
        return encodeJPEGBase64(image, targetWidth: targetWidth, targetHeight: targetHeight, compression: snapshotJPEGQuality)
    }

    static func encodeThumbnail(_ image: CGImage) -> String? {
        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)
        let scale = thumbnailSize / max(sourceWidth, sourceHeight)
        let targetWidth = max(1, Int(sourceWidth * scale))
        let targetHeight = max(1, Int(sourceHeight * scale))
        return encodeJPEGBase64(image, targetWidth: targetWidth, targetHeight: targetHeight, compression: thumbnailJPEGQuality)
    }

    static func decodeImage(from base64: String?) -> NSImage? {
        guard let base64,
              let data = Data(base64Encoded: base64),
              let image = NSImage(data: data) else {
            return nil
        }
        return image
    }

    private static func encodeJPEGBase64(
        _ image: CGImage,
        targetWidth: Int,
        targetHeight: Int,
        compression: CGFloat
    ) -> String? {
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let scaledImage = context.makeImage() else { return nil }

        let nsImage = NSImage(cgImage: scaledImage, size: NSSize(width: targetWidth, height: targetHeight))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compression]) else {
            return nil
        }

        return jpegData.base64EncodedString()
    }
}
