//
//  PhotosLibrary.swift
//  Hypnograph
//
//  Interface to Apple Photos library via PhotoKit.
//  Handles authorization and provides access to PHAssets.
//

import Foundation
import Photos
import AVFoundation

/// Singleton interface to Apple Photos library
final class PhotosLibrary {
    static let shared = PhotosLibrary()

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

    private init() {
        refreshStatus()
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
        return results.objects(in: 0..<results.count)
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
        return results.objects(in: 0..<results.count)
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

    // MARK: - Writing (Future)

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

