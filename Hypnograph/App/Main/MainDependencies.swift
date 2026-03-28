//
//  MainDependencies.swift
//  Hypnograph
//

import Foundation

struct MainDependencies {
    var makePanelHostService: @MainActor () -> FilePanelService
    var photosIntegrationService: PhotosIntegrationService
    var clipHistoryPersistenceService: ClipHistoryPersistenceService

    static let live = MainDependencies(
        makePanelHostService: { FilePanelService() },
        photosIntegrationService: .live,
        clipHistoryPersistenceService: .live
    )
}
