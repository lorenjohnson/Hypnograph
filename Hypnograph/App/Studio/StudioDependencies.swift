//
//  StudioDependencies.swift
//  Hypnograph
//

import Foundation

struct StudioDependencies {
    var makePanelHostService: @MainActor () -> FilePanelService
    var photosIntegrationService: PhotosIntegrationService
    var compositionHistoryPersistenceService: CompositionHistoryPersistenceService

    static let live = StudioDependencies(
        makePanelHostService: { FilePanelService() },
        photosIntegrationService: .live,
        compositionHistoryPersistenceService: .live
    )
}
