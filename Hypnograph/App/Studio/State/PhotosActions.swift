//
//  PhotosActions.swift
//  Hypnograph
//

import Foundation
import HypnoCore

@MainActor
extension Studio {
    var photosAuthorizationStatus: ApplePhotos.AuthorizationStatus {
        state.photosAuthorizationStatus
    }

    func refreshPhotosStatus() -> ApplePhotos.AuthorizationStatus {
        state.refreshPhotosAuthorizationStatus()
    }

    func requestPhotosAccess() async -> ApplePhotos.AuthorizationStatus {
        await state.requestPhotosAuthorizationIfNeeded()
    }
}
