//
//  StudioDependencies.swift
//  Hypnograph
//

import Foundation

struct StudioDependencies {
    var makePanelHostService: @MainActor () -> FilePanelService
    var photosIntegrationService: PhotosIntegrationService

    static let live = StudioDependencies(
        makePanelHostService: { FilePanelService() },
        photosIntegrationService: .live
    )
}
