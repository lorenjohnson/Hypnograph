import Foundation
import AVFoundation
import CoreGraphics
import Photos
import HypnoCore

@MainActor
enum SequenceFCPXMLExporter {
    struct ResultPackage {
        let exportFolderURL: URL
        let documentURL: URL
        let mediaFolderURL: URL
        let manifestURL: URL
        let sourceURLs: [URL]
    }

    enum ExportError: LocalizedError {
        case emptySequence
        case unsupportedSource(String)
        case photosAccessDenied
        case photosAssetMissing(String)
        case photosResourceMissing(String)
        case photosExportFailed(String, String)

        var errorDescription: String? {
            switch self {
            case .emptySequence:
                return "The current sequence has no compositions to export."
            case .unsupportedSource(let description):
                return "The exporter couldn't resolve source media for \(description)."
            case .photosAccessDenied:
                return "Apple Photos access is required to export Photos-backed sources."
            case .photosAssetMissing(let identifier):
                return "Couldn't resolve Apple Photos asset \(identifier) for FCPXML export."
            case .photosResourceMissing(let identifier):
                return "Couldn't find an exportable original resource for Apple Photos asset \(identifier)."
            case .photosExportFailed(let identifier, let reason):
                return "Failed to export Apple Photos asset \(identifier): \(reason)"
            }
        }
    }

    private enum SourceOrigin: String, Encodable {
        case fileSystem = "file"
        case applePhotos = "photos"
    }

    private struct SourceAsset {
        let id: String
        let key: String
        let displayName: String
        let fileURL: URL
        let mediaKind: MediaKind
        let sourceDuration: CMTime
        let hasAudio: Bool
        let sourceOrigin: SourceOrigin
        let isPackagedCopy: Bool
        let originalReference: String
    }

    private struct TimelineLayer {
        let asset: SourceAsset
        let start: CMTime
        let duration: CMTime
        let lane: Int
        let sourceFraming: SourceFraming
    }

    private struct TimelineSegment {
        let offset: CMTime
        let duration: CMTime
        let layers: [TimelineLayer]
    }

    private struct Manifest: Encodable {
        let timelineName: String
        let exportedAt: Date
        let documentPath: String
        let outputWidth: Int
        let outputHeight: Int
        let clips: [Clip]

        struct Clip: Encodable {
            let sequenceIndex: Int
            let compositionID: UUID
            let durationSeconds: Double
            let layers: [Layer]
        }

        struct Layer: Encodable {
            let lane: Int
            let sourceName: String
            let sourceURL: String
            let originalReference: String
            let sourceKind: String
            let sourceOrigin: SourceOrigin
            let packagedInExport: Bool
            let startSeconds: Double
            let durationSeconds: Double
        }
    }

    static func exportCurrentSequence(
        hypnogram: Hypnogram,
        to requestedURL: URL,
        timelineName: String,
        outputSize: CGSize,
        sourceFraming: SourceFraming
    ) async throws -> ResultPackage {
        guard !hypnogram.compositions.isEmpty else {
            throw ExportError.emptySequence
        }

        let fileManager = FileManager.default
        let exportFolderURL = exportFolderURL(for: requestedURL)
        let documentURL = exportFolderURL
            .appendingPathComponent(exportFolderURL.lastPathComponent)
            .appendingPathExtension("fcpxml")
        let mediaFolderURL = exportFolderURL.appendingPathComponent("Media", isDirectory: true)
        let manifestURL = exportFolderURL.appendingPathComponent("manifest.json")

        if fileManager.fileExists(atPath: exportFolderURL.path) {
            try fileManager.removeItem(at: exportFolderURL)
        }
        try fileManager.createDirectory(at: mediaFolderURL, withIntermediateDirectories: true)

        var exportedSourceURLsByKey: [String: URL] = [:]
        var usedMediaFilenames: Set<String> = []
        var canonicalAssetsByKey: [String: SourceAsset] = [:]
        var orderedAssets: [SourceAsset] = []
        var segments: [TimelineSegment] = []
        var manifestClips: [Manifest.Clip] = []

        var offset: CMTime = .zero

        for (compositionIndex, composition) in hypnogram.compositions.enumerated() {
            let compositionDuration = sanitizedDuration(composition.effectiveDuration)
            var timelineLayers: [TimelineLayer] = []
            var manifestLayers: [Manifest.Layer] = []

            for (layerIndex, layer) in composition.layers.enumerated() {
                let resolvedAsset = try await resolveSourceAsset(
                    for: layer,
                    mediaFolderURL: mediaFolderURL,
                    exportedSourceURLsByKey: &exportedSourceURLsByKey,
                    usedMediaFilenames: &usedMediaFilenames
                )

                let asset: SourceAsset
                if let existing = canonicalAssetsByKey[resolvedAsset.key] {
                    asset = existing
                } else {
                    let canonicalAsset = SourceAsset(
                        id: "r\(orderedAssets.count + 2)",
                        key: resolvedAsset.key,
                        displayName: resolvedAsset.displayName,
                        fileURL: resolvedAsset.fileURL,
                        mediaKind: resolvedAsset.mediaKind,
                        sourceDuration: resolvedAsset.sourceDuration,
                        hasAudio: resolvedAsset.hasAudio,
                        sourceOrigin: resolvedAsset.sourceOrigin,
                        isPackagedCopy: resolvedAsset.isPackagedCopy,
                        originalReference: resolvedAsset.originalReference
                    )
                    canonicalAssetsByKey[resolvedAsset.key] = canonicalAsset
                    orderedAssets.append(canonicalAsset)
                    asset = canonicalAsset
                }

                let timeRange = sanitizedTimeRange(
                    for: layer,
                    asset: asset,
                    compositionDuration: compositionDuration
                )

                timelineLayers.append(
                    TimelineLayer(
                        asset: asset,
                        start: timeRange.start,
                        duration: timeRange.duration,
                        lane: layerIndex,
                        sourceFraming: sourceFraming
                    )
                )

                manifestLayers.append(
                    Manifest.Layer(
                        lane: layerIndex,
                        sourceName: asset.displayName,
                        sourceURL: asset.fileURL.path,
                        originalReference: asset.originalReference,
                        sourceKind: asset.mediaKind.rawValue,
                        sourceOrigin: asset.sourceOrigin,
                        packagedInExport: asset.isPackagedCopy,
                        startSeconds: timeRange.start.seconds,
                        durationSeconds: timeRange.duration.seconds
                    )
                )
            }

            segments.append(
                TimelineSegment(
                    offset: offset,
                    duration: compositionDuration,
                    layers: timelineLayers
                )
            )

            manifestClips.append(
                Manifest.Clip(
                    sequenceIndex: compositionIndex,
                    compositionID: composition.id,
                    durationSeconds: compositionDuration.seconds,
                    layers: manifestLayers
                )
            )

            offset = CMTimeAdd(offset, compositionDuration)
        }

        let document = makeDocument(
            timelineName: timelineName,
            assets: orderedAssets,
            segments: segments,
            outputSize: outputSize
        )
        try document.write(to: documentURL, atomically: true, encoding: .utf8)

        let manifest = Manifest(
            timelineName: timelineName,
            exportedAt: Date(),
            documentPath: documentURL.path,
            outputWidth: max(2, Int(outputSize.width.rounded())),
            outputHeight: max(2, Int(outputSize.height.rounded())),
            clips: manifestClips
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return ResultPackage(
            exportFolderURL: exportFolderURL,
            documentURL: documentURL,
            mediaFolderURL: mediaFolderURL,
            manifestURL: manifestURL,
            sourceURLs: orderedAssets.map(\.fileURL)
        )
    }

    private static func resolveSourceAsset(
        for layer: Layer,
        mediaFolderURL: URL,
        exportedSourceURLsByKey: inout [String: URL],
        usedMediaFilenames: inout Set<String>
    ) async throws -> SourceAsset {
        switch layer.mediaClip.file.source {
        case .url(let url):
            let originalFileURL = url.resolvingSymlinksInPath().standardizedFileURL
            let key = "file:\(originalFileURL.path)"
            let packagedURL: URL
            if let existing = exportedSourceURLsByKey[key] {
                packagedURL = existing
            } else {
                let uniqueFilename = makeUniqueFilename(
                    preferredName: originalFileURL.lastPathComponent,
                    usedNames: &usedMediaFilenames
                )
                let outputURL = mediaFolderURL.appendingPathComponent(uniqueFilename)
                try FileManager.default.copyItem(at: originalFileURL, to: outputURL)
                exportedSourceURLsByKey[key] = outputURL
                packagedURL = outputURL
            }

            let asset = AVURLAsset(url: packagedURL)
            return SourceAsset(
                id: "",
                key: key,
                displayName: packagedURL.lastPathComponent,
                fileURL: packagedURL,
                mediaKind: layer.mediaClip.file.mediaKind,
                sourceDuration: quantizedAssetDuration(for: layer),
                hasAudio: asset.tracks(withMediaType: .audio).first != nil,
                sourceOrigin: .fileSystem,
                isPackagedCopy: true,
                originalReference: originalFileURL.path
            )

        case .external(let identifier):
            ApplePhotos.shared.refreshStatus()
            guard ApplePhotos.shared.status.canRead else {
                throw ExportError.photosAccessDenied
            }
            guard let asset = ApplePhotos.shared.fetchAsset(localIdentifier: identifier) else {
                throw ExportError.photosAssetMissing(identifier)
            }

            let exportedURL: URL
            let key = "photos:\(identifier)"
            if let existing = exportedSourceURLsByKey[key] {
                exportedURL = existing
            } else {
                guard let resource = preferredResource(for: asset) else {
                    throw ExportError.photosResourceMissing(identifier)
                }

                let preferredName = resource.originalFilename.isEmpty
                    ? fallbackPhotosFilename(for: asset, identifier: identifier)
                    : resource.originalFilename
                let uniqueFilename = makeUniqueFilename(
                    preferredName: preferredName,
                    usedNames: &usedMediaFilenames
                )
                let outputURL = mediaFolderURL.appendingPathComponent(uniqueFilename)
                try await exportPhotosResource(resource, to: outputURL, identifier: identifier)
                exportedSourceURLsByKey[key] = outputURL
                exportedURL = outputURL
            }

            let avAsset = AVURLAsset(url: exportedURL)
            return SourceAsset(
                id: "",
                key: key,
                displayName: exportedURL.lastPathComponent,
                fileURL: exportedURL,
                mediaKind: layer.mediaClip.file.mediaKind,
                sourceDuration: quantizedAssetDuration(for: layer),
                hasAudio: avAsset.tracks(withMediaType: .audio).first != nil,
                sourceOrigin: .applePhotos,
                isPackagedCopy: true,
                originalReference: identifier
            )
        }
    }

    private static func sanitizedTimeRange(
        for layer: Layer,
        asset: SourceAsset,
        compositionDuration: CMTime
    ) -> (start: CMTime, duration: CMTime) {
        let defaultDuration = quantizedTime(layer.mediaClip.duration)
        let maximumTimelineDuration = quantizedTime(compositionDuration)
        guard asset.mediaKind == .video, asset.sourceDuration.seconds.isFinite else {
            return (.zero, CMTimeMinimum(defaultDuration, maximumTimelineDuration))
        }

        let normalizedSourceDuration = asset.sourceDuration
        let requestedStart = quantizedTime(layer.mediaClip.startTime)
        let clampedStart = requestedStart.seconds >= normalizedSourceDuration.seconds
            ? CMTimeSubtract(normalizedSourceDuration, frameDuration)
            : requestedStart
        let nonNegativeStart = CMTimeMaximum(.zero, clampedStart)
        let availableDuration = CMTimeMaximum(.zero, CMTimeSubtract(normalizedSourceDuration, nonNegativeStart))
        let clampedDuration = CMTimeMinimum(defaultDuration, availableDuration)
        let boundedDuration = CMTimeMinimum(quantizedTime(clampedDuration), maximumTimelineDuration)
        return (nonNegativeStart, CMTimeMaximum(frameDuration, boundedDuration))
    }

    private static func sanitizedDuration(_ time: CMTime) -> CMTime {
        guard time.isValid, !time.isIndefinite, time.seconds.isFinite else {
            return frameDuration
        }
        return quantizedTime(CMTime(seconds: max(frameDuration.seconds, time.seconds), preferredTimescale: 600))
    }

    private static func quantizedAssetDuration(for layer: Layer) -> CMTime {
        if layer.mediaClip.file.mediaKind == .video {
            return sanitizedDuration(layer.mediaClip.file.duration)
        }

        return CMTime(seconds: 3600, preferredTimescale: frameTimescale)
    }

    private static let frameTimescale: CMTimeScale = 30
    private static let frameDuration = CMTime(value: 1, timescale: frameTimescale)

    private static func quantizedTime(_ time: CMTime) -> CMTime {
        guard time.isValid, !time.isIndefinite, time.seconds.isFinite else {
            return frameDuration
        }

        let seconds = max(0, time.seconds)
        let frames = max(1, Int64((seconds * Double(frameTimescale)).rounded()))
        return CMTime(value: frames, timescale: frameTimescale)
    }

    private static func preferredResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        switch asset.mediaType {
        case .video:
            return resources.first(where: { $0.type == .pairedVideo || $0.type == .fullSizeVideo || $0.type == .video })
                ?? resources.first
        case .image:
            return resources.first(where: { $0.type == .fullSizePhoto || $0.type == .photo })
                ?? resources.first
        default:
            return resources.first
        }
    }

    private static func exportPhotosResource(
        _ resource: PHAssetResource,
        to outputURL: URL,
        identifier: String
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: outputURL, options: nil) { error in
                if let error {
                    continuation.resume(throwing: ExportError.photosExportFailed(identifier, error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static func fallbackPhotosFilename(for asset: PHAsset, identifier: String) -> String {
        switch asset.mediaType {
        case .video:
            return "Photos-\(identifier).mov"
        case .image:
            return "Photos-\(identifier).jpeg"
        default:
            return "Photos-\(identifier)"
        }
    }

    private static func makeUniqueFilename(preferredName: String, usedNames: inout Set<String>) -> String {
        let url = URL(fileURLWithPath: preferredName)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var candidate = preferredName
        var suffix = 2
        while usedNames.contains(candidate.lowercased()) {
            if ext.isEmpty {
                candidate = "\(base)-\(suffix)"
            } else {
                candidate = "\(base)-\(suffix).\(ext)"
            }
            suffix += 1
        }
        usedNames.insert(candidate.lowercased())
        return candidate
    }

    private static func exportFolderURL(for requestedURL: URL) -> URL {
        let normalizedURL = requestedURL.standardizedFileURL
        if normalizedURL.pathExtension.isEmpty {
            return normalizedURL
        }
        return normalizedURL.deletingPathExtension()
    }

    private static func makeDocument(
        timelineName: String,
        assets: [SourceAsset],
        segments: [TimelineSegment],
        outputSize: CGSize
    ) -> String {
        let formatID = "r1"
        let width = max(2, Int(outputSize.width.rounded()))
        let height = max(2, Int(outputSize.height.rounded()))
        let sequenceDuration = segments.reduce(CMTime.zero) { partial, segment in
            CMTimeAdd(partial, segment.duration)
        }

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<fcpxml version=\"1.8\">")
        lines.append("  <resources>")
        lines.append("    <format id=\"\(formatID)\" frameDuration=\"1/30s\" fieldOrder=\"progressive\" width=\"\(width)\" height=\"\(height)\"/>")

        for asset in assets {
            var attributes: [String] = [
                "id=\"\(asset.id)\"",
                "name=\"\(xmlEscaped(asset.displayName))\"",
                "start=\"0s\"",
                "duration=\"\(timeString(for: asset.sourceDuration))\"",
                "hasVideo=\"1\"",
                "hasAudio=\"\(asset.hasAudio ? "1" : "0")\"",
                "format=\"\(formatID)\"",
                "src=\"\(xmlEscaped(asset.fileURL.absoluteURL.absoluteString))\""
            ]
            if asset.hasAudio {
                attributes.append("audioSources=\"1\"")
                attributes.append("audioChannels=\"2\"")
                attributes.append("audioRate=\"48000\"")
            }
            lines.append("    <asset \(attributes.joined(separator: " "))/>\n")
        }

        lines.append("  </resources>")
        lines.append("  <library>")
        lines.append("    <event name=\"Hypnograph Exports\">")
        lines.append("      <project name=\"\(xmlEscaped(timelineName))\">")
        lines.append(
            "        <sequence format=\"\(formatID)\" duration=\"\(timeString(for: sequenceDuration))\" tcStart=\"0s\" tcFormat=\"NDF\" audioLayout=\"stereo\" audioRate=\"48k\">"
        )
        lines.append("          <spine>")

        for segment in segments {
            lines.append(contentsOf: storyLines(for: segment))
        }

        lines.append("          </spine>")
        lines.append("        </sequence>")
        lines.append("      </project>")
        lines.append("    </event>")
        lines.append("  </library>")
        lines.append("</fcpxml>")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func storyLines(for segment: TimelineSegment) -> [String] {
        guard !segment.layers.isEmpty else {
            return [
                "            <gap offset=\"\(timeString(for: segment.offset))\" start=\"0s\" duration=\"\(timeString(for: segment.duration))\"/>"
            ]
        }

        if segment.layers.count == 1, let onlyLayer = segment.layers.first, onlyLayer.duration == segment.duration {
            return singleAssetClipLine(
                layer: onlyLayer,
                offset: timeString(for: segment.offset)
            )
        }

        var lines: [String] = []
        lines.append(
            "            <gap offset=\"\(timeString(for: segment.offset))\" start=\"0s\" duration=\"\(timeString(for: segment.duration))\">"
        )
        for layer in segment.layers {
            let laneAttribute = layer.lane > 0 ? " lane=\"\(layer.lane)\"" : ""
            lines.append(contentsOf: assetClipLines(
                indent: "              ",
                layer: layer,
                offset: "0s",
                laneAttribute: laneAttribute
            ))
        }
        lines.append("            </gap>")
        return lines
    }

    private static func singleAssetClipLine(layer: TimelineLayer, offset: String) -> [String] {
        assetClipLines(indent: "            ", layer: layer, offset: offset, laneAttribute: "")
    }

    private static func assetClipLines(
        indent: String,
        layer: TimelineLayer,
        offset: String,
        laneAttribute: String
    ) -> [String] {
        let opening = "\(indent)<asset-clip name=\"\(xmlEscaped(layer.asset.displayName))\" ref=\"\(layer.asset.id)\" offset=\"\(offset)\" start=\"\(timeString(for: layer.start))\" duration=\"\(timeString(for: layer.duration))\"\(laneAttribute)>"
        let conform = layer.sourceFraming == .fill
            ? "\(indent)  <adjust-conform type=\"fill\"/>"
            : nil
        let closing = "\(indent)</asset-clip>"

        return [opening] + (conform.map { [$0] } ?? []) + [closing]
    }

    private static func timeString(for time: CMTime) -> String {
        guard time.isValid, !time.isIndefinite else {
            return "0s"
        }

        let normalized = time.convertScale(600, method: .default)
        if normalized.timescale == 0 {
            return "0s"
        }

        let value = Int64(normalized.value)
        let scale = Int64(normalized.timescale)
        if value % scale == 0 {
            return "\(value / scale)s"
        }

        let divisor = gcd(abs(value), abs(scale))
        return "\(value / divisor)/\(scale / divisor)s"
    }

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var x = a
        var y = b
        while y != 0 {
            let remainder = x % y
            x = y
            y = remainder
        }
        return max(1, x)
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
