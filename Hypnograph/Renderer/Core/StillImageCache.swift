//
//  StillImageCache.swift
//  Hypnograph
//
//  Created by Loren Johnson on 25.11.25.
//

import CoreImage
import CoreGraphics
import ImageIO

/// Lightweight cache so we only ever try to decode a still image once per URL.
/// This avoids repeated slow disk/decoder work and repeated CGImageSource errors.
/// NOTE: Cache grows unbounded - call clear() periodically to free memory.
enum StillImageCache {
    private static var ciCache: [URL: CIImage?] = [:]
    private static var cgCache: [URL: CGImage?] = [:]
    private static let lock = NSLock()

    /// Clear all cached images to free memory
    static func clear() {
        lock.lock(); defer { lock.unlock() }
        ciCache.removeAll()
        cgCache.removeAll()
        print("🧹 StillImageCache: Cleared all cached images")
    }

    /// Get current cache size (number of cached images)
    static func cacheSize() -> (ciImages: Int, cgImages: Int) {
        lock.lock(); defer { lock.unlock() }
        return (ciCache.count, cgCache.count)
    }

    static func ciImage(for url: URL) -> CIImage? {
        lock.lock(); defer { lock.unlock() }

        if let cached = ciCache[url] { return cached }

        // First try CIImage directly
        if let ci = CIImage(
            contentsOf: url,
            options: [CIImageOption.applyOrientationProperty: true]
        ) {
            ciCache[url] = ci
            return ci
        }

        // Fallback via CGImage (handles formats CIImage sometimes hates)
        if let cg = cgImage(for: url) {
            let ci = CIImage(cgImage: cg)
            ciCache[url] = ci
            return ci
        }

        print("❌ StillImageCache: failed to decode CIImage from \(url.lastPathComponent)")
        ciCache[url] = nil
        return nil
    }

    static func cgImage(for url: URL) -> CGImage? {
        lock.lock(); defer { lock.unlock() }

        if let cached = cgCache[url] { return cached }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            cgCache[url] = nil
            return nil
        }

        cgCache[url] = img
        return img
    }
}
