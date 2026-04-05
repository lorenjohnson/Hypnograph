//
//  WindowHostBridge.swift
//  Hypnograph
//

import SwiftUI

struct WindowHostBridge: NSViewRepresentable {
    @ObservedObject var hostService: WindowHostService
    let showHypnograms: Bool
    let showSources: Bool
    let showNewClips: Bool
    let showOutputSettings: Bool
    let showComposition: Bool
    let showEffects: Bool
    let showPlayerControls: Bool
    let expectedParentFullScreen: Bool
    let panelFrames: [String: CGRect]
    let playerControlsLayoutSignature: Int
    let autoHideWindows: Bool
    let keyboardAccessibilityOverridesEnabled: Bool
    let onPanelVisibilityChanged: (String, Bool) -> Void
    let onPanelFrameChanged: (String, CGRect) -> Void
    let onPanelsAutoHiddenChanged: (Bool) -> Void
    let hypnogramsContent: AnyView
    let sourcesContent: AnyView
    let newClipsContent: AnyView
    let outputSettingsContent: AnyView
    let compositionContent: AnyView
    let effectsContent: AnyView
    let playerControlsContent: AnyView

    final class Coordinator {
        var hostService: WindowHostService

        init(hostService: WindowHostService) {
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
            showSources: showSources,
            showNewClips: showNewClips,
            showOutputSettings: showOutputSettings,
            showComposition: showComposition,
            showEffects: showEffects,
            showPlayerControls: showPlayerControls,
            expectedParentFullScreen: expectedParentFullScreen,
            panelFrames: panelFrames,
            playerControlsLayoutSignature: playerControlsLayoutSignature,
            autoHideWindows: autoHideWindows,
            keyboardAccessibilityOverridesEnabled: keyboardAccessibilityOverridesEnabled,
            onPanelVisibilityChanged: onPanelVisibilityChanged,
            onPanelFrameChanged: onPanelFrameChanged,
            onPanelsAutoHiddenChanged: onPanelsAutoHiddenChanged,
            hypnogramsContent: hypnogramsContent,
            sourcesContent: sourcesContent,
            newClipsContent: newClipsContent,
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
