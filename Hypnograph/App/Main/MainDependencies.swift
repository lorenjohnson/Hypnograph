//
//  MainDependencies.swift
//  Hypnograph
//

import Foundation

struct MainDependencies {
    var makePanelHostService: @MainActor () -> MainPanelHostService
    var photosIntegrationService: MainPhotosIntegrationService
    var clipHistoryPersistenceService: ClipHistoryPersistenceService

    static let live = MainDependencies(
        makePanelHostService: { MainPanelHostService() },
        photosIntegrationService: .live,
        clipHistoryPersistenceService: .live
    )
}
