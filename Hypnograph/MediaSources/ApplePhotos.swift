//
//  ApplePhotos.swift
//  Hypnograph
//
//  Interface to Apple Photos library via PhotoKit.
//  Handles authorization and provides access to PHAssets.
//

import Foundation
import Photos
import AVFoundation

/// Singleton interface to Apple Photos library
final class ApplePhotos {
    static let shared = ApplePhotos()

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

    // MARK: - Image Loading

    /// Request CIImage for a PHAsset (image)
    func requestCIImage(for asset: PHAsset) async -> CIImage? {
        guard status.canRead else { return nil }
        guard asset.mediaType == .image else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            // Request full-size image data
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, orientation, _ in
                guard let data = data else {
                    continuation.resume(returning: nil)
                    return
                }

                // Create CIImage from data
                guard let ciImage = CIImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }

                // Apply orientation correction using CGImagePropertyOrientation
                let oriented = ciImage.oriented(orientation)
                continuation.resume(returning: oriented)
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

    // MARK: - Album Management

    /// Folder and album names used by Hypnograph
    private static let folderName = "Hypnograph"

    enum AlbumName: String {
        case sources = "Sources"
        case saved = "Saved"
    }

    /// Find an existing folder by name
    private func findFolder(named name: String) -> PHCollectionList? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", name)
        let folders = PHCollectionList.fetchCollectionLists(with: .folder, subtype: .any, options: options)
        return folders.firstObject
    }

    /// Find an existing album by name within a folder
    private func findAlbum(named name: String, inFolder folder: PHCollectionList) -> PHAssetCollection? {
        let collections = PHCollection.fetchCollections(in: folder, options: nil)
        for i in 0..<collections.count {
            if let album = collections.object(at: i) as? PHAssetCollection,
               album.localizedTitle == name {
                return album
            }
        }
        return nil
    }

    /// Find or create the Hypnograph folder
    private func findOrCreateFolder() async -> PHCollectionList? {
        if let existing = findFolder(named: Self.folderName) {
            return existing
        }

        guard status.canWrite else {
            print("ApplePhotos: cannot create folder - no write access")
            return nil
        }

        var placeholderID: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHCollectionListChangeRequest.creationRequestForCollectionList(withTitle: Self.folderName)
                placeholderID = request.placeholderForCreatedCollectionList.localIdentifier
            }
        } catch {
            print("ApplePhotos: failed to create folder '\(Self.folderName)' - \(error)")
            return nil
        }

        guard let id = placeholderID else { return nil }
        let result = PHCollectionList.fetchCollectionLists(withLocalIdentifiers: [id], options: nil)
        return result.firstObject
    }

    /// Find or create an album inside the Hypnograph folder
    func findOrCreateAlbum(named albumName: AlbumName) async -> PHAssetCollection? {
        guard let folder = await findOrCreateFolder() else {
            print("ApplePhotos: cannot create album - folder not available")
            return nil
        }

        // Check if album already exists in folder
        if let existing = findAlbum(named: albumName.rawValue, inFolder: folder) {
            return existing
        }

        guard status.canWrite else {
            print("ApplePhotos: cannot create album '\(albumName.rawValue)' - no write access")
            return nil
        }

        // Create album inside folder
        var albumPlaceholderID: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let albumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName.rawValue)
                albumPlaceholderID = albumRequest.placeholderForCreatedAssetCollection.localIdentifier

                // Add album to folder
                guard let folderRequest = PHCollectionListChangeRequest(for: folder) else { return }
                folderRequest.addChildCollections([albumRequest.placeholderForCreatedAssetCollection] as NSArray)
            }
        } catch {
            print("ApplePhotos: failed to create album '\(albumName.rawValue)' - \(error)")
            return nil
        }

        guard let id = albumPlaceholderID else { return nil }
        let result = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
        return result.firstObject
    }

    /// Fetch assets from an album
    func fetchAssets(from album: PHAssetCollection, limit: Int? = nil) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let limit = limit {
            options.fetchLimit = limit
        }

        let results = PHAsset.fetchAssets(in: album, options: options)
        return results.objects(at: IndexSet(integersIn: 0..<results.count))
    }

    /// Get or create the Sources album, populating with recent assets if newly created
    func getOrCreateSourcesAlbum() async -> PHAssetCollection? {
        // Check if folder/album already exist
        if let folder = findFolder(named: Self.folderName),
           let existing = findAlbum(named: AlbumName.sources.rawValue, inFolder: folder) {
            return existing
        }

        guard status.canWrite else {
            print("ApplePhotos: cannot create sources album - no write access")
            return nil
        }

        // Create folder and album
        guard let album = await findOrCreateAlbum(named: .sources) else { return nil }

        // Fetch last 500 assets by date (photos and videos)
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 500

        let allAssets = PHAsset.fetchAssets(with: options)
        let assets = allAssets.objects(at: IndexSet(integersIn: 0..<allAssets.count))

        if assets.isEmpty {
            print("ApplePhotos: no assets to add to sources album")
            return album
        }

        // Add assets to album
        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
                request.addAssets(assets as NSFastEnumeration)
            }
            print("ApplePhotos: added \(assets.count) assets to 'Hypnograph/Sources'")
        } catch {
            print("ApplePhotos: failed to add assets to album - \(error)")
        }

        return album
    }

    // MARK: - Saving to Photos

    /// Save an image file to Photos and add to the Saved album
    func saveImage(at url: URL) async -> Bool {
        guard status.canWrite else {
            print("ApplePhotos: cannot save image - no write access")
            return false
        }

        guard let album = await findOrCreateAlbum(named: .saved) else {
            print("ApplePhotos: cannot save image - failed to get/create album")
            return false
        }

        var assetPlaceholder: PHObjectPlaceholder?

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                assetPlaceholder = request?.placeholderForCreatedAsset
            }
        } catch {
            print("ApplePhotos: failed to create image asset - \(error)")
            return false
        }

        // Add to album
        guard let placeholder = assetPlaceholder else { return false }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let albumRequest = PHAssetCollectionChangeRequest(for: album) else { return }
                albumRequest.addAssets([placeholder] as NSArray)
            }
            print("ApplePhotos: saved image to 'Hypnograph/Saved'")
            return true
        } catch {
            print("ApplePhotos: failed to add image to album - \(error)")
            return false
        }
    }

    /// Save a video file to Photos and add to the Saved album
    func saveVideo(at url: URL) async -> Bool {
        guard status.canWrite else {
            print("ApplePhotos: cannot save video - no write access")
            return false
        }

        guard let album = await findOrCreateAlbum(named: .saved) else {
            print("ApplePhotos: cannot save video - failed to get/create album")
            return false
        }

        var assetPlaceholder: PHObjectPlaceholder?

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                assetPlaceholder = request?.placeholderForCreatedAsset
            }
        } catch {
            print("ApplePhotos: failed to create video asset - \(error)")
            return false
        }

        // Add to album
        guard let placeholder = assetPlaceholder else { return false }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let albumRequest = PHAssetCollectionChangeRequest(for: album) else { return }
                albumRequest.addAssets([placeholder] as NSArray)
            }
            print("ApplePhotos: saved video to 'Hypnograph/Saved'")
            return true
        } catch {
            print("ApplePhotos: failed to add video to album - \(error)")
            return false
        }
    }
}

