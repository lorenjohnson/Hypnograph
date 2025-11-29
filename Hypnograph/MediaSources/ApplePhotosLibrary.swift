//
//  ApplePhotosLibrary.swift
//  Hypnograph
//
//  Interface to Apple Photos library via PhotoKit.
//  Handles authorization and provides access to PHAssets.
//

import Foundation
import Photos
import AVFoundation

/// Singleton interface to Apple Photos library
final class ApplePhotosLibrary {
    static let shared = ApplePhotosLibrary()

    // MARK: - Authorization

    enum AuthorizationStatus {
        case notDetermined
        case authorized
        case limited
        case denied
        case restricted

        var canRead: Bool {
            self == .authorized || self == .limited
        }

        var canWrite: Bool {
            self == .authorized
        }
    }

    /// Current authorization status (cached, call checkAuthorization() to refresh)
    private(set) var status: AuthorizationStatus = .notDetermined

    /// In-memory cache of hidden asset UUIDs (loaded from disk on init)
    private(set) var cachedHiddenUUIDs: Set<String> = []

    /// Path to cache file
    private var hiddenIdentifiersCacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let hypnographDir = appSupport.appendingPathComponent("Hypnograph", isDirectory: true)
        return hypnographDir.appendingPathComponent("apple-photos-hidden-local-identifiers.txt")
    }

    private init() {
        refreshStatus()
        loadCachedHiddenIdentifiers()
    }

    /// Refresh cached status from system
    func refreshStatus() {
        let systemStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        status = mapStatus(systemStatus)
    }

    /// Request read/write authorization. Returns the new status.
    @discardableResult
    func requestAuthorization() async -> AuthorizationStatus {
        let systemStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = mapStatus(systemStatus)
        print("PhotosLibrary: authorization status = \(status)")
        return status
    }

    private func mapStatus(_ systemStatus: PHAuthorizationStatus) -> AuthorizationStatus {
        switch systemStatus {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    // MARK: - Hidden Identifiers Cache

    /// Load cached hidden identifiers from disk into memory
    private func loadCachedHiddenIdentifiers() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: hiddenIdentifiersCacheURL.path) else {
            cachedHiddenUUIDs = []
            return
        }

        guard let content = try? String(contentsOf: hiddenIdentifiersCacheURL, encoding: .utf8) else {
            cachedHiddenUUIDs = []
            return
        }

        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        cachedHiddenUUIDs = Set(lines)
    }

    /// Refresh hidden identifiers cache from Apple Photos.
    /// Fetches all hidden assets, extracts UUIDs, writes to cache file, updates in-memory cache.
    /// Returns count of hidden assets found.
    @discardableResult
    func refreshHiddenIdentifiersCache() -> Int {
        guard status.canRead else { return 0 }

        let assets = fetchHiddenAssets()
        var uuids = Set<String>()

        for asset in assets {
            let identifier = asset.localIdentifier
            if let slashIndex = identifier.firstIndex(of: "/") {
                let uuid = String(identifier[..<slashIndex])
                uuids.insert(uuid)
            } else {
                uuids.insert(identifier)
            }
        }

        // Write to file
        let fm = FileManager.default
        let dir = hiddenIdentifiersCacheURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let content = uuids.sorted().joined(separator: "\n")
        try? content.write(to: hiddenIdentifiersCacheURL, atomically: true, encoding: .utf8)

        cachedHiddenUUIDs = uuids
        return assets.count
    }

    /// Check if a filename (without extension) matches any cached hidden asset UUID
    func isHiddenAsset(filenameBase: String) -> Bool {
        cachedHiddenUUIDs.contains(filenameBase)
    }

    // MARK: - Fetching Assets

    /// Fetch video assets from Photos library
    func fetchVideos(limit: Int? = nil) -> [PHAsset] {
        guard status.canRead else { return [] }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let limit = limit {
            options.fetchLimit = limit
        }

        let results = PHAsset.fetchAssets(with: options)
        return results.objects(at: IndexSet(integersIn: 0..<results.count))
    }

    /// Fetch image assets from Photos library
    func fetchImages(limit: Int? = nil) -> [PHAsset] {
        guard status.canRead else { return [] }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let limit = limit {
            options.fetchLimit = limit
        }

        let results = PHAsset.fetchAssets(with: options)
        return results.objects(at: IndexSet(integersIn: 0..<results.count))
    }

    /// Fetch a specific asset by local identifier
    func fetchAsset(localIdentifier: String) -> PHAsset? {
        let results = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return results.firstObject
    }

    // MARK: - AVAsset Loading

    /// Request AVAsset for a PHAsset (video)
    func requestAVAsset(for asset: PHAsset) async -> AVAsset? {
        guard status.canRead else { return nil }
        guard asset.mediaType == .video else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    // MARK: - Hidden Assets

    /// Fetch all hidden assets from Photos library
    /// Returns array of PHAssets from the Hidden album
    /// Note: Requires "Use Touch ID for Hidden Album" to be disabled in Photos settings
    func fetchHiddenAssets() -> [PHAsset] {
        guard status.canRead else { return [] }

        // Fetch the Hidden smart album
        let hiddenAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumAllHidden,
            options: nil
        )

        guard let hiddenAlbum = hiddenAlbums.firstObject else {
            print("PhotosLibrary: Hidden album not found")
            return []
        }

        // Must explicitly include hidden assets - this is off by default
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = true

        let hiddenAssets = PHAsset.fetchAssets(in: hiddenAlbum, options: fetchOptions)

        if hiddenAssets.count == 0 && hiddenAlbum.estimatedAssetCount == NSNotFound {
            print("PhotosLibrary: Hidden album protected - disable Touch ID in Photos settings to access")
        }

        return hiddenAssets.objects(at: IndexSet(integersIn: 0..<hiddenAssets.count))
    }

    // MARK: - Debug / Inspection

    /// Log detailed info about a specific asset by local identifier (or UUID prefix)
    func logAssetInfo(identifier: String) {
        // Try exact match first
        var asset = fetchAsset(localIdentifier: identifier)

        // If not found, try as UUID prefix (search all assets)
        if asset == nil {
            print("PhotosLibrary: No exact match for '\(identifier)', searching by UUID prefix...")
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "localIdentifier BEGINSWITH %@", identifier)
            let results = PHAsset.fetchAssets(with: options)
            asset = results.firstObject
        }

        guard let asset = asset else {
            print("PhotosLibrary: Asset not found for identifier '\(identifier)'")
            return
        }

        print("=== Asset Info: \(identifier) ===")
        print("  Local Identifier: \(asset.localIdentifier)")
        print("  Media Type: \(asset.mediaType == .image ? "image" : asset.mediaType == .video ? "video" : "other")")
        print("  Media Subtypes: \(asset.mediaSubtypes.rawValue)")
        print("  Creation Date: \(asset.creationDate?.description ?? "nil")")
        print("  Modification Date: \(asset.modificationDate?.description ?? "nil")")
        print("  Duration: \(asset.duration) seconds")
        print("  Pixel Width: \(asset.pixelWidth)")
        print("  Pixel Height: \(asset.pixelHeight)")
        print("  Is Favorite: \(asset.isFavorite)")
        print("  Is Hidden: \(asset.isHidden)")
        print("  Source Type: \(asset.sourceType.rawValue)")

        // Get resource info (file paths, etc)
        let resources = PHAssetResource.assetResources(for: asset)
        print("  Resources (\(resources.count)):")
        for (idx, resource) in resources.enumerated() {
            print("    [\(idx)] type=\(resource.type.rawValue) filename=\(resource.originalFilename) uti=\(resource.uniformTypeIdentifier)")
        }
        print("===================================")
    }

    /// Set favorite status for an asset
    func setFavorite(_ asset: PHAsset, isFavorite: Bool) async -> Bool {
        guard status.canWrite else { return false }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = isFavorite
            }
            return true
        } catch {
            print("PhotosLibrary: failed to set favorite - \(error)")
            return false
        }
    }
}

