//
//  StudioWindowHostService.swift
//  Hypnograph
//

import SwiftUI
import AppKit

private enum StudioPanelKind: String {
    case sources
    case newClips
    case outputSettings
    case composition
    case effects

    var title: String {
        switch self {
        case .sources: return "Sources"
        case .newClips: return "New Clips"
        case .outputSettings: return "Output Settings"
        case .composition: return "Composition"
        case .effects: return "Effects"
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .sources: return CGSize(width: 420, height: 620)
        case .newClips: return CGSize(width: 360, height: 560)
        case .outputSettings: return CGSize(width: 360, height: 360)
        case .composition: return CGSize(width: 420, height: 720)
        case .effects: return CGSize(width: 420, height: 720)
        }
    }

    var minSize: CGSize {
        switch self {
        case .sources: return CGSize(width: 360, height: 420)
        case .newClips: return CGSize(width: 300, height: 360)
        case .outputSettings: return CGSize(width: 300, height: 260)
        case .composition: return CGSize(width: 340, height: 420)
        case .effects: return CGSize(width: 340, height: 420)
        }
    }

    var defaultOrigin: (NSRect, CGSize) -> CGPoint {
        switch self {
        case .sources:
            return { parentFrame, _ in
                CGPoint(x: parentFrame.maxX + 16, y: parentFrame.maxY - 620)
            }
        case .newClips:
            return { parentFrame, size in
                CGPoint(x: parentFrame.minX - size.width - 16, y: parentFrame.maxY - size.height - 36)
            }
        case .outputSettings:
            return { parentFrame, size in
                CGPoint(x: parentFrame.minX - size.width - 16, y: parentFrame.maxY - size.height - 420)
            }
        case .composition:
            return { parentFrame, _ in
                CGPoint(x: parentFrame.maxX + 16, y: parentFrame.maxY - 720)
            }
        case .effects:
            return { parentFrame, _ in
                CGPoint(x: parentFrame.maxX + 16, y: parentFrame.maxY - 360)
            }
        }
    }

    var autosaveName: String {
        "Hypnograph.Studio.\(rawValue)"
    }
}

private final class StudioChildPanel: NSPanel {
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
final class StudioWindowHostService: ObservableObject {
    private struct ManagedPanel {
        let panel: StudioChildPanel
        let host: NSHostingController<AnyView>
    }

    private weak var parentWindow: NSWindow?
    private var panels: [StudioPanelKind: ManagedPanel] = [:]
    private var parentCloseObserver: NSObjectProtocol?

    func sync(
        parentWindow: NSWindow?,
        showSources: Bool,
        showNewClips: Bool,
        showOutputSettings: Bool,
        showComposition: Bool,
        showEffects: Bool,
        sourcesContent: AnyView,
        newClipsContent: AnyView,
        outputSettingsContent: AnyView,
        compositionContent: AnyView,
        effectsContent: AnyView
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

        syncPanel(kind: .sources, visible: showSources, content: sourcesContent, parentWindow: parentWindow)
        syncPanel(kind: .newClips, visible: showNewClips, content: newClipsContent, parentWindow: parentWindow)
        syncPanel(kind: .outputSettings, visible: showOutputSettings, content: outputSettingsContent, parentWindow: parentWindow)
        syncPanel(kind: .composition, visible: showComposition, content: compositionContent, parentWindow: parentWindow)
        syncPanel(kind: .effects, visible: showEffects, content: effectsContent, parentWindow: parentWindow)
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
        kind: StudioPanelKind,
        visible: Bool,
        content: AnyView,
        parentWindow: NSWindow
    ) {
        if visible {
            let managed = ensurePanel(kind: kind, parentWindow: parentWindow)
            managed.host.rootView = content

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

    private func ensurePanel(kind: StudioPanelKind, parentWindow: NSWindow) -> ManagedPanel {
        if let existing = panels[kind] {
            return existing
        }

        let frame = defaultFrame(kind: kind, parentWindow: parentWindow)
        let panel = StudioChildPanel(
            contentRect: frame,
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = kind.title
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.level = parentWindow.level
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.backgroundColor = .black
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.minSize = kind.minSize
        panel.setFrameAutosaveName(kind.autosaveName)
        _ = panel.setFrameUsingName(kind.autosaveName, force: false)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.onUserInteraction = { [weak self, weak panel] in
            guard let self, let panel else { return }
            bringToFront(panel)
        }

        let host = NSHostingController(rootView: AnyView(EmptyView()))
        host.view.appearance = NSAppearance(named: .darkAqua)
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

    private func defaultFrame(kind: StudioPanelKind, parentWindow: NSWindow) -> NSRect {
        let parentFrame = parentWindow.frame
        let size = kind.defaultSize
        let origin = kind.defaultOrigin(parentFrame, size)
        return NSRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
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
