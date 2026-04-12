import Foundation
import CoreLocation
import Photos
import HypnoCore

enum LayerMetadataFormatter {
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
            guard let asset = ApplePhotos.shared.fetchAsset(localIdentifier: identifier) else {
                return layer.mediaClip.file.displayName
            }
            let resources = PHAssetResource.assetResources(for: asset)
            if let resource = resources.first(where: { $0.type == .pairedVideo || $0.type == .video || $0.type == .photo }) {
                return resource.originalFilename
            }
            return resources.first?.originalFilename ?? layer.mediaClip.file.displayName
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
            guard let asset = ApplePhotos.shared.fetchAsset(localIdentifier: identifier) else { return [] }
            var parts: [String] = []
            if let date = asset.creationDate {
                parts.append(dateFormatter.string(from: date))
            }
            if let location = asset.location {
                parts.append(locationString(location))
            }
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
