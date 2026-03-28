//
//  PhotosIntegrationService.swift
//  Hypnograph
//

import Foundation
import HypnoCore

struct PhotosIntegrationService {
    var authorizationStatus: ApplePhotos.AuthorizationStatus {
        ApplePhotos.shared.status
    }

    var canWrite: Bool {
        authorizationStatus.canWrite
    }

    func refreshStatus() {
        ApplePhotos.shared.refreshStatus()
    }

    func requestAuthorization() async -> ApplePhotos.AuthorizationStatus {
        await ApplePhotos.shared.requestAuthorization()
    }

    func saveImage(at url: URL) async -> Bool {
        await ApplePhotos.shared.saveImage(at: url)
    }

    func saveVideo(at url: URL) async -> Bool {
        await ApplePhotos.shared.saveVideo(at: url)
    }

    static let live = PhotosIntegrationService()
}
