//
//  StudioDependencies.swift
//  Hypnograph
//

import Foundation

struct StudioDependencies {
    var makePanelHostService: @MainActor () -> FilePanelService
    var photosIntegrationService: PhotosIntegrationService
    var clipHistoryPersistenceService: ClipHistoryPersistenceService

    static let live = StudioDependencies(
        makePanelHostService: { FilePanelService() },
        photosIntegrationService: .live,
        clipHistoryPersistenceService: .live
    )
}
