//
//  EffectsComposerPanelWindows.swift
//  Hypnograph
//

import SwiftUI

struct EffectsComposerPanelHostBridge: NSViewRepresentable {
    @ObservedObject var hostService: EffectsComposerPanelHostService
    let showCodePanel: Bool
    let showInspectorPanel: Bool
    let showManifestPanel: Bool
    let showLiveControlsPanel: Bool
    let panelOpacity: Double
    let codeContent: AnyView
    let inspectorContent: AnyView
    let manifestContent: AnyView
    let liveControlsContent: AnyView

    final class Coordinator {
        var hostService: EffectsComposerPanelHostService

        init(hostService: EffectsComposerPanelHostService) {
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
            showCodePanel: showCodePanel,
            showInspectorPanel: showInspectorPanel,
            showManifestPanel: showManifestPanel,
            showLiveControlsPanel: showLiveControlsPanel,
            panelOpacity: panelOpacity,
            codeContent: codeContent,
            inspectorContent: inspectorContent,
            manifestContent: manifestContent,
            liveControlsContent: liveControlsContent
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.hostService.teardown()
    }
}
