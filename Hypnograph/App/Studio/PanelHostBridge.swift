//
//  PanelHostBridge.swift
//  Hypnograph
//

import SwiftUI

struct PanelHostBridge: NSViewRepresentable {
    @ObservedObject var hostService: PanelHostService
    let showSequence: Bool
    let showHypnograms: Bool
    let showSources: Bool
    let showNewCompositions: Bool
    let showOutputSettings: Bool
    let showComposition: Bool
    let showEffects: Bool
    let showPlayerControls: Bool
    let expectedParentFullScreen: Bool
    let panelFrames: [String: CGRect]
    let panelOrder: [String]
    let autoHidePanels: Bool
    let keyboardAccessibilityOverridesEnabled: Bool
    let onPanelVisibilityChanged: (String, Bool) -> Void
    let onPanelFrameChanged: (String, CGRect) -> Void
    let onPanelOrderChanged: ([String]) -> Void
    let onPanelsAutoHiddenChanged: (Bool) -> Void
    let sequenceContent: AnyView
    let hypnogramsContent: AnyView
    let sourcesContent: AnyView
    let newCompositionsContent: AnyView
    let outputSettingsContent: AnyView
    let compositionContent: AnyView
    let effectsContent: AnyView
    let playerControlsContent: AnyView

    final class Coordinator {
        var hostService: PanelHostService

        init(hostService: PanelHostService) {
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
            showSequence: showSequence,
            showHypnograms: showHypnograms,
            showSources: showSources,
            showNewCompositions: showNewCompositions,
            showOutputSettings: showOutputSettings,
            showComposition: showComposition,
            showEffects: showEffects,
            showPlayerControls: showPlayerControls,
            expectedParentFullScreen: expectedParentFullScreen,
            panelFrames: panelFrames,
            panelOrder: panelOrder,
            autoHidePanels: autoHidePanels,
            keyboardAccessibilityOverridesEnabled: keyboardAccessibilityOverridesEnabled,
            onPanelVisibilityChanged: onPanelVisibilityChanged,
            onPanelFrameChanged: onPanelFrameChanged,
            onPanelOrderChanged: onPanelOrderChanged,
            onPanelsAutoHiddenChanged: onPanelsAutoHiddenChanged,
            sequenceContent: sequenceContent,
            hypnogramsContent: hypnogramsContent,
            sourcesContent: sourcesContent,
            newCompositionsContent: newCompositionsContent,
            outputSettingsContent: outputSettingsContent,
            compositionContent: compositionContent,
            effectsContent: effectsContent,
            playerControlsContent: playerControlsContent
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.hostService.teardown()
    }
}
