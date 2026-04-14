import Foundation
import CoreLocation
import Photos
import HypnoCore

@MainActor
enum LayerMetadataFormatter {
    struct Summary {
        let fileName: String
        let dateText: String?
        let locationText: String?
        let totalLengthText: String
    }

    private static var cachedFileNamesByIdentifier: [String: String] = [:]
    private static var cachedMetadataPartsByIdentifier: [String: [String]] = [:]

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func displayLabel(for layer: Layer) -> String {
        let summary = summary(for: layer)
        var parts: [String] = []

        if let dateText = summary.dateText, !dateText.isEmpty {
            parts.append(dateText)
        }

        if let locationText = summary.locationText, !locationText.isEmpty {
            parts.append(locationText)
        }

        parts.append(summary.fileName)
        parts.append(summary.totalLengthText)
        return parts.joined(separator: " | ")
    }

    static func summary(for layer: Layer) -> Summary {
        let metadata = metadataParts(for: layer)
        let dateText = metadata.first
        let locationText = metadata.dropFirst().first

        return Summary(
            fileName: fileName(for: layer),
            dateText: dateText,
            locationText: locationText,
            totalLengthText: totalLengthText(for: layer)
        )
    }

    static func fileName(for layer: Layer) -> String {
        switch layer.mediaClip.file.source {
        case .url(let url):
            return url.lastPathComponent
        case .external(let identifier):
            if let cached = cachedFileNamesByIdentifier[identifier] {
                return cached
            }
            guard let asset = ApplePhotos.shared.fetchAsset(localIdentifier: identifier) else {
                return layer.mediaClip.file.displayName
            }
            let resources = PHAssetResource.assetResources(for: asset)
            let resolvedName: String
            if let resource = resources.first(where: { $0.type == .pairedVideo || $0.type == .video || $0.type == .photo }) {
                resolvedName = resource.originalFilename
            } else {
                resolvedName = resources.first?.originalFilename ?? layer.mediaClip.file.displayName
            }
            cachedFileNamesByIdentifier[identifier] = resolvedName
            return resolvedName
        }
    }

    static func metadataParts(for layer: Layer) -> [String] {
        switch layer.mediaClip.file.source {
        case .url(let url):
            guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) else {
                return []
            }
            if let date = values.creationDate ?? values.contentModificationDate {
                return [dateFormatter.string(from: date)]
            }
            return []
        case .external(let identifier):
            if let cached = cachedMetadataPartsByIdentifier[identifier] {
                return cached
            }
            guard let asset = ApplePhotos.shared.fetchAsset(localIdentifier: identifier) else { return [] }
            var parts: [String] = []
            if let date = asset.creationDate {
                parts.append(dateFormatter.string(from: date))
            }
            if let location = asset.location {
                parts.append(locationString(location))
            }
            cachedMetadataPartsByIdentifier[identifier] = parts
            return parts
        }
    }

    static func totalLengthText(for layer: Layer) -> String {
        let seconds: Double
        if layer.mediaClip.file.mediaKind == .video {
            seconds = max(0.1, layer.mediaClip.file.duration.seconds)
        } else {
            seconds = max(0.1, layer.mediaClip.duration.seconds)
        }

        return formatTime(seconds)
    }

    static func locationString(_ location: CLLocation) -> String {
        let lat = abs(location.coordinate.latitude)
        let lon = abs(location.coordinate.longitude)
        let latSuffix = location.coordinate.latitude >= 0 ? "N" : "S"
        let lonSuffix = location.coordinate.longitude >= 0 ? "E" : "W"
        return String(format: "%.2f%@/%.2f%@", lat, latSuffix, lon, lonSuffix)
    }

    private static func formatTime(_ seconds: Double) -> String {
        let clampedSeconds = max(0, seconds)
        if clampedSeconds >= 60 {
            let minutes = Int(clampedSeconds) / 60
            let remainder = clampedSeconds.truncatingRemainder(dividingBy: 60)
            return String(format: "%d:%04.1f", minutes, remainder)
        }
        return String(format: "%.1fs", clampedSeconds)
    }
}
