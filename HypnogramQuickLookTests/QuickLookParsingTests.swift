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

    @Test func quickLookParsesSessionJSON() throws {
        let duration = CMTime(seconds: 2, preferredTimescale: 600)
        let file = MediaFile(source: .url(URL(fileURLWithPath: "/tmp/quicklook.mov")), mediaKind: .video, duration: duration)
        let mediaClip = MediaClip(file: file, startTime: .zero, duration: duration)
        let layer = HypnogramLayer(mediaClip: mediaClip)

        let snapshotData = try makeSnapshotData(size: CGSize(width: 6, height: 6))
        let snapshotBase64 = snapshotData.base64EncodedString()
        let chain = EffectChain(name: "Global", effects: [
            EffectDefinition(type: "BasicEffect"),
            EffectDefinition(type: "FrameDifferenceEffect")
        ])
        let hypnogram = Hypnogram(layers: [layer], targetDuration: duration, effectChain: chain)
        var session = HypnographSession(hypnograms: [hypnogram])
        session.snapshot = snapshotBase64

        let data = try JSONEncoder().encode(session)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            #expect(Bool(false), "Expected JSON object")
            return
        }

        let hypnograms = json["hypnograms"] as? [[String: Any]]
        let first = hypnograms?.first
        let layers = first?["layers"] as? [[String: Any]]
        let firstLayer = layers?.first
        let effectChain = first?["effectChain"] as? [String: Any]
        let effects = effectChain?["effects"] as? [[String: Any]]
        let targetDuration = first?["targetDuration"] as? [String: Any]
        let seconds = targetDuration?["seconds"] as? Double

        #expect(hypnograms?.count == 1)
        #expect(layers?.count == 1)
        #expect(firstLayer?["mediaClip"] != nil)
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
