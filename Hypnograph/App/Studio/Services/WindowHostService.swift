//
//  WindowHostService.swift
//  Hypnograph
//

import SwiftUI
import AppKit

private enum WindowKind: String {
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

    var windowStateID: String {
        "\(rawValue)Window"
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

    var maxWidth: CGFloat {
        defaultSize.width * 1.5
    }

    var minSize: CGSize {
        switch self {
        case .sources: return CGSize(width: 360, height: 420)
        case .newClips: return CGSize(width: defaultSize.width, height: 360)
        case .outputSettings: return CGSize(width: defaultSize.width, height: 260)
        case .composition: return CGSize(width: defaultSize.width, height: 420)
        case .effects: return CGSize(width: defaultSize.width, height: 420)
        }
    }

    var shouldFitHeightToContent: Bool {
        self != .effects
    }

    var fixedHeightPadding: CGFloat {
        16
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

private final class ChildWindowPanel: NSPanel {
    var onUserInteraction: (() -> Void)?
    var onCloseRequest: (() -> Void)?

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

    override func performClose(_ sender: Any?) {
        if let onCloseRequest {
            onCloseRequest()
            return
        }
        super.performClose(sender)
    }
}

@MainActor
final class WindowHostService: NSObject, ObservableObject, NSWindowDelegate {
    private struct ManagedPanel {
        let panel: ChildWindowPanel
        let host: NSHostingController<AnyView>
    }

    private weak var parentWindow: NSWindow?
    private var panels: [WindowKind: ManagedPanel] = [:]
    private var parentCloseObserver: NSObjectProtocol?
    private var onPanelVisibilityChanged: ((String, Bool) -> Void)?

    func sync(
        parentWindow: NSWindow?,
        showSources: Bool,
        showNewClips: Bool,
        showOutputSettings: Bool,
        showComposition: Bool,
        showEffects: Bool,
        onPanelVisibilityChanged: @escaping (String, Bool) -> Void,
        sourcesContent: AnyView,
        newClipsContent: AnyView,
        outputSettingsContent: AnyView,
        compositionContent: AnyView,
        effectsContent: AnyView
    ) {
        self.onPanelVisibilityChanged = onPanelVisibilityChanged

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
        kind: WindowKind,
        visible: Bool,
        content: AnyView,
        parentWindow: NSWindow
    ) {
        if visible {
            let managed = ensurePanel(kind: kind, parentWindow: parentWindow, content: content)
            applySizing(for: kind, managed: managed)

            if managed.panel.parent == nil {
                parentWindow.addChildWindow(managed.panel, ordered: .above)
            }
            if !managed.panel.isVisible {
                managed.panel.orderFront(nil)
            }
        } else if let managed = panels[kind] {
            if managed.panel.parent === parentWindow {
                parentWindow.removeChildWindow(managed.panel)
            }
            managed.panel.orderOut(nil)
        }
    }

    private func ensurePanel(kind: WindowKind, parentWindow: NSWindow, content: AnyView) -> ManagedPanel {
        if let existing = panels[kind] {
            return existing
        }

        let frame = defaultFrame(kind: kind, parentWindow: parentWindow)
        let panel = ChildWindowPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = kind.title
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.level = parentWindow.level
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.backgroundColor = .black
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.minSize = kind.minSize
        panel.maxSize = CGSize(width: kind.maxWidth, height: .greatestFiniteMagnitude)
        panel.setFrameAutosaveName(kind.autosaveName)
        _ = panel.setFrameUsingName(kind.autosaveName, force: false)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        installTitleAccessory(for: panel, title: kind.title)
        panel.onUserInteraction = { [weak self, weak panel] in
            guard let self, let panel else { return }
            bringToFront(panel)
        }
        panel.onCloseRequest = { [weak self, weak panel] in
            guard let self else { return }
            self.handleCloseRequest(for: kind, panel: panel)
        }

        let host = NSHostingController(rootView: content)
        host.view.appearance = NSAppearance(named: .darkAqua)
        panel.contentViewController = host

        let managed = ManagedPanel(panel: panel, host: host)
        panels[kind] = managed
        return managed
    }

    private func installTitleAccessory(for panel: NSPanel, title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 22))
        container.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = container
        accessory.layoutAttribute = .left
        panel.addTitlebarAccessoryViewController(accessory)
    }

    private func applySizing(for kind: WindowKind, managed: ManagedPanel) {
        let panel = managed.panel
        let clampedWidth = min(max(panel.frame.width, kind.minSize.width), kind.maxWidth)
        let maxInitialHeight = maximumInitialHeight(for: panel)

        panel.contentView?.frame = NSRect(origin: .zero, size: CGSize(width: clampedWidth, height: panel.frame.height))
        managed.host.view.frame = NSRect(origin: .zero, size: CGSize(width: clampedWidth, height: panel.frame.height))
        managed.host.view.layoutSubtreeIfNeeded()

        if kind.shouldFitHeightToContent {
            let measuredHeight = min(
                max(
                    kind.minSize.height,
                    managed.host.view.fittingSize.height + kind.fixedHeightPadding
                ),
                maxInitialHeight
            )

            panel.minSize = CGSize(width: kind.minSize.width, height: measuredHeight)
            panel.maxSize = CGSize(width: kind.maxWidth, height: measuredHeight)

            let targetFrame = NSRect(
                x: panel.frame.origin.x,
                y: panel.frame.origin.y,
                width: clampedWidth,
                height: measuredHeight
            )
            if panel.frame.size != targetFrame.size {
                panel.setFrame(targetFrame, display: true)
            }
        } else {
            panel.minSize = kind.minSize
            panel.maxSize = CGSize(width: kind.maxWidth, height: .greatestFiniteMagnitude)

            if panel.frame.width != clampedWidth {
                let targetFrame = NSRect(
                    x: panel.frame.origin.x,
                    y: panel.frame.origin.y,
                    width: clampedWidth,
                    height: panel.frame.height
                )
                panel.setFrame(targetFrame, display: true)
            }
        }
    }

    private func maximumInitialHeight(for panel: NSPanel) -> CGFloat {
        let visibleHeight = panel.screen?.visibleFrame.height
            ?? parentWindow?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 900

        return max(320, visibleHeight - 140)
    }
    private func configureParentWindowForFullScreen(_ window: NSWindow) {
        var behavior = window.collectionBehavior
        if !behavior.contains(.fullScreenPrimary) {
            behavior.insert(.fullScreenPrimary)
            window.collectionBehavior = behavior
        }
    }

    private func defaultFrame(kind: WindowKind, parentWindow: NSWindow) -> NSRect {
        let parentFrame = parentWindow.frame
        let size = kind.defaultSize
        let origin = kind.defaultOrigin(parentFrame, size)
        return NSRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    private func hideAllPanels() {
        panels.values.forEach { managed in
            if let parent = managed.panel.parent {
                parent.removeChildWindow(managed.panel)
            }
            managed.panel.orderOut(nil)
        }
    }

    private func handleCloseRequest(for kind: WindowKind, panel: NSPanel?) {
        if let panel, let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        panel?.orderOut(nil)
        onPanelVisibilityChanged?(kind.windowStateID, false)
    }

    private func bringToFront(_ panel: NSPanel) {
        if let parentWindow, panel.parent === parentWindow {
            parentWindow.removeChildWindow(panel)
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func kind(for panel: NSWindow) -> WindowKind? {
        panels.first { $0.value.panel === panel }?.key
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let kind = kind(for: sender) else { return true }
        handleCloseRequest(for: kind, panel: sender as? NSPanel)
        return false
    }
}
