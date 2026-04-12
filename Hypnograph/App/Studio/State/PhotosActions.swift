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

    func openApplePhotosPrivacySettings() {
        Environment.openApplePhotosPrivacySettings()
    }

    func revealSourcesWindow() {
        panels.setPanelsHidden(false)
        NotificationCenter.default.post(name: ContentView.studioShowPanelsNowNotification, object: nil)
        state.settingsStore.update { $0.newCompositionsPanelTab = .sources }
        panels.setPanelVisible("newCompositionsPanel", visible: true)
    }
}
