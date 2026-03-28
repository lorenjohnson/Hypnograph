//
//  StudioPanelWindows.swift
//  Hypnograph
//

import SwiftUI

struct StudioPanelHostBridge: NSViewRepresentable {
    @ObservedObject var hostService: StudioWindowHostService
    let showSources: Bool
    let showNewClips: Bool
    let showOutputSettings: Bool
    let showComposition: Bool
    let showEffects: Bool
    let sourcesContent: AnyView
    let newClipsContent: AnyView
    let outputSettingsContent: AnyView
    let compositionContent: AnyView
    let effectsContent: AnyView

    final class Coordinator {
        var hostService: StudioWindowHostService

        init(hostService: StudioWindowHostService) {
            self.hostService = hostService
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hostService: hostService)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostService = hostService
        context.coordinator.hostService.sync(
            parentWindow: nsView.window,
            showSources: showSources,
            showNewClips: showNewClips,
            showOutputSettings: showOutputSettings,
            showComposition: showComposition,
            showEffects: showEffects,
            sourcesContent: sourcesContent,
            newClipsContent: newClipsContent,
            outputSettingsContent: outputSettingsContent,
            compositionContent: compositionContent,
            effectsContent: effectsContent
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.hostService.teardown()
    }
}
