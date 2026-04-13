//
//  CompositionPreviewGenerator.swift
//  Hypnograph
//

import CoreGraphics
import Foundation
import HypnoCore

enum CompositionPreviewGenerator {
    static func makePreviewImages(for composition: Composition) async -> CompositionPreviewImages? {
        guard let previewFrame = await makePreviewFrame(for: composition) else {
            return nil
        }

        return CompositionPreviewImageCodec.makePreviewImages(from: previewFrame)
    }

    static func makePreviewFrame(for composition: Composition) async -> CGImage? {
        guard let layer = previewLayer(for: composition) else { return nil }

        return await MediaThumbnailGenerator.makeCGImage(
            source: layer.mediaClip.file.source,
            mediaKind: layer.mediaClip.file.mediaKind,
            sourceDurationSeconds: max(0.1, layer.mediaClip.file.duration.seconds),
            time: layer.mediaClip.startTime,
            maximumSize: CGSize(
                width: CompositionPreviewImageCodec.snapshotWidth,
                height: CompositionPreviewImageCodec.snapshotHeight
            )
        )
    }

    private static func previewLayer(for composition: Composition) -> Layer? {
        composition.layers.reversed().first(where: { $0.opacity > 0.001 }) ?? composition.layers.last
    }
}
