//
//  QuickLookParsingTests.swift
//  HypnogramQuickLookTests
//
//  Created by Loren Johnson on 15.11.25.
//

import Testing
import CoreMedia
import CoreGraphics
import CoreImage
import AppKit
import HypnoCore

struct QuickLookParsingTests {

    @Test func quickLookParsesRecipeJSON() throws {
        let duration = CMTime(seconds: 2, preferredTimescale: 600)
        let file = MediaFile(source: .url(URL(fileURLWithPath: "/tmp/quicklook.mov")), mediaKind: .video, duration: duration)
        let clip = VideoClip(file: file, startTime: .zero, duration: duration)
        let source = HypnogramSource(clip: clip)

        let snapshotData = try makeSnapshotData(size: CGSize(width: 6, height: 6))
        let snapshotBase64 = snapshotData.base64EncodedString()
        var recipe = HypnogramRecipe(sources: [source], targetDuration: duration, mode: .montage)
        recipe.snapshot = snapshotBase64
        recipe.effectChain = EffectChain(name: "Global", effects: [
            EffectDefinition(type: "BasicEffect"),
            EffectDefinition(type: "FrameDifferenceEffect")
        ])

        let data = try JSONEncoder().encode(recipe)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            #expect(Bool(false), "Expected JSON object")
            return
        }

        let sources = json["sources"] as? [[String: Any]]
        let effectChain = json["effectChain"] as? [String: Any]
        let effects = effectChain?["effects"] as? [[String: Any]]
        let targetDuration = json["targetDuration"] as? [String: Any]
        let seconds = targetDuration?["seconds"] as? Double

        #expect(sources?.count == 1)
        #expect(effects?.count == 2)
        #expect(seconds == duration.seconds)
        #expect((json["snapshot"] as? String)?.isEmpty == false)
    }

    private func makeSnapshotData(size: CGSize) throws -> Data {
        let image = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 1))
            .cropped(to: CGRect(origin: .zero, size: size))
        let context = CIContext()
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw TestImageError.failedToCreateCGImage
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw TestImageError.failedToWriteImage
        }
        return data
    }

    private enum TestImageError: Error {
        case failedToCreateCGImage
        case failedToWriteImage
    }
}
