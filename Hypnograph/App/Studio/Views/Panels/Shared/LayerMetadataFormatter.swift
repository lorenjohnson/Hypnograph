import Foundation
import CoreLocation
import Photos
import HypnoCore

@MainActor
enum LayerMetadataFormatter {
    private static var cachedFileNamesByIdentifier: [String: String] = [:]
    private static var cachedMetadataPartsByIdentifier: [String: [String]] = [:]

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func displayLabel(for layer: Layer) -> String {
        let fileName = fileName(for: layer)
        let metadata = metadataParts(for: layer)
        guard !metadata.isEmpty else { return fileName }
        return ([fileName] + metadata).joined(separator: " | ")
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

    static func locationString(_ location: CLLocation) -> String {
        let lat = abs(location.coordinate.latitude)
        let lon = abs(location.coordinate.longitude)
        let latSuffix = location.coordinate.latitude >= 0 ? "N" : "S"
        let lonSuffix = location.coordinate.longitude >= 0 ? "E" : "W"
        return String(format: "%.2f%@/%.2f%@", lat, latSuffix, lon, lonSuffix)
    }
}
