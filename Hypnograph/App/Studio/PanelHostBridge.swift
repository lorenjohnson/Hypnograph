//
//  PanelHostBridge.swift
//  Hypnograph
//

import SwiftUI

struct PanelHostBridge: NSViewRepresentable {
    @ObservedObject var hostService: PanelHostService
    let showHypnograms: Bool
    let showNewCompositions: Bool
    let showProperties: Bool
    let showEffects: Bool
    let showPlayerControls: Bool
    let expectedParentFullScreen: Bool
    let panelFrames: [String: CGRect]
    let panelOrder: [String]
    let panelOpacity: Double
    let autoHidePanels: Bool
    let keyboardAccessibilityOverridesEnabled: Bool
    let onPanelVisibilityChanged: (String, Bool) -> Void
    let onPanelFrameChanged: (String, CGRect) -> Void
    let onPanelOrderChanged: ([String]) -> Void
    let onPanelsAutoHiddenChanged: (Bool) -> Void
    let hypnogramsContent: AnyView
    let newCompositionsContent: AnyView
    let propertiesContent: AnyView
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
            showHypnograms: showHypnograms,
            showNewCompositions: showNewCompositions,
            showProperties: showProperties,
            showEffects: showEffects,
            showPlayerControls: showPlayerControls,
            expectedParentFullScreen: expectedParentFullScreen,
            panelFrames: panelFrames,
            panelOrder: panelOrder,
            panelOpacity: panelOpacity,
            autoHidePanels: autoHidePanels,
            keyboardAccessibilityOverridesEnabled: keyboardAccessibilityOverridesEnabled,
            onPanelVisibilityChanged: onPanelVisibilityChanged,
            onPanelFrameChanged: onPanelFrameChanged,
            onPanelOrderChanged: onPanelOrderChanged,
            onPanelsAutoHiddenChanged: onPanelsAutoHiddenChanged,
            hypnogramsContent: hypnogramsContent,
            newCompositionsContent: newCompositionsContent,
            propertiesContent: propertiesContent,
            effectsContent: effectsContent,
            playerControlsContent: playerControlsContent
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.hostService.teardown()
    }
}
