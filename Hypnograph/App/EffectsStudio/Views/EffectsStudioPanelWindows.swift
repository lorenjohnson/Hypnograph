//
//  EffectsStudioPanelWindows.swift
//  Hypnograph
//

import SwiftUI
import AppKit

@MainActor
final class EffectsStudioTabKeyMonitor: ObservableObject {
    private var keyMonitor: Any?
    private var shouldHandleEvent: ((NSEvent) -> Bool)?
    private var onTabPressed: (() -> Void)?

    func start(
        shouldHandleEvent: @escaping (NSEvent) -> Bool,
        onTabPressed: @escaping () -> Void
    ) {
        stop()
        self.shouldHandleEvent = shouldHandleEvent
        self.onTabPressed = onTabPressed

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.shouldHandleEvent?(event) == true else { return event }
            if event.isARepeat {
                return nil
            }
            self.onTabPressed?()
            return nil
        }
    }

    func stop() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        shouldHandleEvent = nil
        onTabPressed = nil
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }
}

private enum EffectsStudioPanelKind: String, CaseIterable {
    case code
    case parameters
    case manifest
    case liveControls

    var title: String {
        switch self {
        case .code: return "Code"
        case .parameters: return "Parameters"
        case .manifest: return "Manifest"
        case .liveControls: return "Live Controls"
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .code: return CGSize(width: 760, height: 560)
        case .parameters: return CGSize(width: 460, height: 620)
        case .manifest: return CGSize(width: 460, height: 460)
        case .liveControls: return CGSize(width: 420, height: 520)
        }
    }

    var minSize: CGSize {
        switch self {
        case .code: return CGSize(width: 420, height: 280)
        case .parameters: return CGSize(width: 360, height: 360)
        case .manifest: return CGSize(width: 340, height: 280)
        case .liveControls: return CGSize(width: 320, height: 300)
        }
    }

    var defaultOffset: CGPoint {
        switch self {
        case .code: return CGPoint(x: 36, y: 80)
        case .parameters: return CGPoint(x: 820, y: 70)
        case .manifest: return CGPoint(x: 860, y: 160)
        case .liveControls: return CGPoint(x: 900, y: 260)
        }
    }

    var autosaveName: String {
        "Hypnograph.EffectsStudio.\(rawValue)"
    }
}

private final class EffectsStudioChildPanel: NSPanel {
    var onUserInteraction: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func toggleFullScreen(_ sender: Any?) {
        if let parent {
            parent.toggleFullScreen(sender)
            return
        }
        super.toggleFullScreen(sender)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            onUserInteraction?()
        }
        super.sendEvent(event)
    }
}

@MainActor
final class EffectsStudioPanelWindowController: ObservableObject {
    private struct ManagedPanel {
        let panel: EffectsStudioChildPanel
        let host: NSHostingController<AnyView>
    }

    private weak var parentWindow: NSWindow?
    private var panels: [EffectsStudioPanelKind: ManagedPanel] = [:]
    private var parentCloseObserver: NSObjectProtocol?

    func sync(
        parentWindow: NSWindow?,
        showCodePanel: Bool,
        showInspectorPanel: Bool,
        showManifestPanel: Bool,
        showLiveControlsPanel: Bool,
        panelOpacity: Double,
        codeContent: AnyView,
        inspectorContent: AnyView,
        manifestContent: AnyView,
        liveControlsContent: AnyView
    ) {
        guard let parentWindow else {
            hideAllPanels()
            return
        }

        if self.parentWindow !== parentWindow {
            detachFromCurrentParent()
            removeParentCloseObserver()
            self.parentWindow = parentWindow
            installParentCloseObserver(for: parentWindow)
        }

        guard parentWindow.isVisible else {
            hideAllPanels()
            return
        }

        configureParentWindowForFullScreen(parentWindow)

        let opacity = min(max(panelOpacity, 0.15), 1.0)
        syncPanel(kind: .code, visible: showCodePanel, opacity: opacity, content: codeContent, parentWindow: parentWindow)
        syncPanel(kind: .parameters, visible: showInspectorPanel, opacity: opacity, content: inspectorContent, parentWindow: parentWindow)
        syncPanel(kind: .manifest, visible: showManifestPanel, opacity: opacity, content: manifestContent, parentWindow: parentWindow)
        syncPanel(kind: .liveControls, visible: showLiveControlsPanel, opacity: opacity, content: liveControlsContent, parentWindow: parentWindow)
    }

    func teardown() {
        hideAllPanels()
        detachFromCurrentParent()
        removeParentCloseObserver()
        panels.values.forEach { $0.panel.close() }
        panels.removeAll()
        parentWindow = nil
    }

    private func syncPanel(
        kind: EffectsStudioPanelKind,
        visible: Bool,
        opacity: Double,
        content: AnyView,
        parentWindow: NSWindow
    ) {
        if visible {
            let managed = ensurePanel(kind: kind, parentWindow: parentWindow)
            managed.host.rootView = content
            managed.panel.alphaValue = opacity

            if managed.panel.parent == nil {
                parentWindow.addChildWindow(managed.panel, ordered: .above)
            }
            if !managed.panel.isVisible {
                managed.panel.orderFront(nil)
            }
        } else if let managed = panels[kind] {
            managed.panel.orderOut(nil)
        }
    }

    private func ensurePanel(kind: EffectsStudioPanelKind, parentWindow: NSWindow) -> ManagedPanel {
        if let existing = panels[kind] {
            return existing
        }

        let frame = defaultFrame(kind: kind, parentWindow: parentWindow)
        let panel = EffectsStudioChildPanel(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.level = parentWindow.level
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.minSize = kind.minSize
        panel.setFrameAutosaveName(kind.autosaveName)
        _ = panel.setFrameUsingName(kind.autosaveName, force: false)
        panel.onUserInteraction = { [weak self, weak panel] in
            guard let self, let panel else { return }
            bringToFront(panel)
        }

        let host = NSHostingController(rootView: AnyView(EmptyView()))
        panel.contentViewController = host

        let managed = ManagedPanel(panel: panel, host: host)
        panels[kind] = managed
        return managed
    }

    private func configureParentWindowForFullScreen(_ window: NSWindow) {
        var behavior = window.collectionBehavior
        if !behavior.contains(.fullScreenPrimary) {
            behavior.insert(.fullScreenPrimary)
            window.collectionBehavior = behavior
        }
    }

    private func defaultFrame(kind: EffectsStudioPanelKind, parentWindow: NSWindow) -> NSRect {
        let parentFrame = parentWindow.frame
        let size = kind.defaultSize
        let offset = kind.defaultOffset
        let x = parentFrame.minX + offset.x
        let y = parentFrame.maxY - offset.y - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func hideAllPanels() {
        panels.values.forEach { $0.panel.orderOut(nil) }
    }

    private func bringToFront(_ panel: NSPanel) {
        if let parentWindow, panel.parent === parentWindow {
            parentWindow.removeChildWindow(panel)
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func detachFromCurrentParent() {
        guard let currentParent = parentWindow else { return }
        panels.values.forEach { managed in
            if managed.panel.parent === currentParent {
                currentParent.removeChildWindow(managed.panel)
            }
        }
    }

    private func installParentCloseObserver(for window: NSWindow) {
        parentCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleParentWillClose()
            }
        }
    }

    private func removeParentCloseObserver() {
        if let observer = parentCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            parentCloseObserver = nil
        }
    }

    private func handleParentWillClose() {
        hideAllPanels()
        detachFromCurrentParent()
        parentWindow = nil
    }
}

struct EffectsStudioPanelHostBridge: NSViewRepresentable {
    @ObservedObject var controller: EffectsStudioPanelWindowController
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
        var controller: EffectsStudioPanelWindowController
        init(controller: EffectsStudioPanelWindowController) {
            self.controller = controller
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.controller = controller
        context.coordinator.controller.sync(
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
        coordinator.controller.teardown()
    }
}
