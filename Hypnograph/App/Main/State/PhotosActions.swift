//
//  PhotosActions.swift
//  Hypnograph
//

import Foundation
import HypnoCore

@MainActor
extension Main {
    var photosAuthorizationStatus: ApplePhotos.AuthorizationStatus {
        photosIntegrationService.authorizationStatus
    }

    func refreshPhotosStatus() -> ApplePhotos.AuthorizationStatus {
        photosIntegrationService.refreshStatus()
        return photosIntegrationService.authorizationStatus
    }

    func requestPhotosAccess() async -> ApplePhotos.AuthorizationStatus {
        let status = await photosIntegrationService.requestAuthorization()
        photosIntegrationService.refreshStatus()
        if status.canRead {
            await state.refreshPhotosLibrariesAfterAuthorization()
        }
        return photosIntegrationService.authorizationStatus
    }
}
