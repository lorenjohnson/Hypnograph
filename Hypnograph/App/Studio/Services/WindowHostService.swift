//
//  WindowHostService.swift
//  Hypnograph
//

import SwiftUI
import AppKit

private enum WindowKind: String {
    case hypnograms
    case sources
    case newClips
    case outputSettings
    case composition
    case effects
    case playerControls

    var title: String {
        switch self {
        case .hypnograms: return "Hypnograms"
        case .sources: return "Sources"
        case .newClips: return "New Compositions"
        case .outputSettings: return "Output Settings"
        case .composition: return "Composition"
        case .effects: return "Effect Chains"
        case .playerControls: return "Playback Controls"
        }
    }

    var windowStateID: String {
        switch self {
        case .hypnograms:
            return "hypnogramList"
        default:
            return "\(rawValue)Window"
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .hypnograms: return CGSize(width: 420, height: 520)
        case .sources: return CGSize(width: 420, height: 620)
        case .newClips: return CGSize(width: 360, height: 560)
        case .outputSettings: return CGSize(width: 360, height: 360)
        case .composition: return CGSize(width: 420, height: 720)
        case .effects: return CGSize(width: 420, height: 720)
        case .playerControls: return CGSize(width: 920, height: 170)
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .playerControls:
            return 1100
        default:
            return defaultSize.width * 1.5
        }
    }

    var minSize: CGSize {
        switch self {
        case .hypnograms: return CGSize(width: 360, height: 320)
        case .sources: return CGSize(width: 360, height: 420)
        case .newClips: return CGSize(width: defaultSize.width, height: 360)
        case .outputSettings: return CGSize(width: defaultSize.width, height: 260)
        case .composition: return CGSize(width: defaultSize.width, height: 420)
        case .effects: return CGSize(width: defaultSize.width, height: 420)
        case .playerControls: return CGSize(width: 720, height: 120)
        }
    }

    var shouldFitHeightToContent: Bool {
        switch self {
        case .effects, .hypnograms:
            return false
        default:
            return true
        }
    }

    var allowsBackgroundDragging: Bool {
        switch self {
        case .composition, .effects, .playerControls:
            return false
        default:
            return true
        }
    }

    var fixedHeightPadding: CGFloat {
        switch self {
        case .playerControls:
            return 0
        default:
            return 16
        }
    }

    var defaultOrigin: (NSRect, CGSize) -> CGPoint {
        switch self {
        case .hypnograms:
            return { parentFrame, size in
                CGPoint(x: parentFrame.minX - size.width - 16, y: parentFrame.maxY - size.height - 36)
            }
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
        case .playerControls:
            return { parentFrame, size in
                CGPoint(
                    x: parentFrame.midX - (size.width / 2),
                    y: parentFrame.minY + 12
                )
            }
        }
    }

    var autosaveName: String {
        "Hypnograph.Studio.\(rawValue)"
    }

    var styleMask: NSWindow.StyleMask {
        switch self {
        case .playerControls:
            return [.titled, .closable, .fullSizeContentView, .utilityWindow]
        default:
            return [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow]
        }
    }

    var isResizable: Bool {
        self != .playerControls
    }

    var backgroundColor: NSColor {
        .black
    }

    var hasShadow: Bool {
        true
    }

    var usesTitlebarChrome: Bool {
        true
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
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel:
            onUserInteraction?()
        default:
            break
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
    private var requestedVisibility: [WindowKind: Bool] = [:]
    private var parentCloseObserver: NSObjectProtocol?
    private var onPanelVisibilityChanged: ((String, Bool) -> Void)?
    private var onPanelsAutoHiddenChanged: ((Bool) -> Void)?
    private var panelLayoutSignatures: [WindowKind: Int] = [:]
    private var autoHideWindowsEnabled = false
    private var keyboardAccessibilityOverridesEnabled = true
    private var autoHideTimer: Timer?
    private var lastMouseLocation: NSPoint = NSEvent.mouseLocation
    private var lastActivityTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var panelsAutoHidden = false
    private var hasInitializedVisiblePanelPresentation = false

    private let autoHideIdleSeconds: TimeInterval = 3.0

    func sync(
        parentWindow: NSWindow?,
        showHypnograms: Bool,
        showSources: Bool,
        showNewClips: Bool,
        showOutputSettings: Bool,
        showComposition: Bool,
        showEffects: Bool,
        showPlayerControls: Bool,
        playerControlsLayoutSignature: Int,
        autoHideWindows: Bool,
        keyboardAccessibilityOverridesEnabled: Bool,
        onPanelVisibilityChanged: @escaping (String, Bool) -> Void,
        onPanelsAutoHiddenChanged: @escaping (Bool) -> Void,
        hypnogramsContent: AnyView,
        sourcesContent: AnyView,
        newClipsContent: AnyView,
        outputSettingsContent: AnyView,
        compositionContent: AnyView,
        effectsContent: AnyView,
        playerControlsContent: AnyView
    ) {
        self.onPanelVisibilityChanged = onPanelVisibilityChanged
        self.onPanelsAutoHiddenChanged = onPanelsAutoHiddenChanged
        onPanelsAutoHiddenChanged(panelsAutoHidden)
        let keyboardOverrideJustEnabled = !self.keyboardAccessibilityOverridesEnabled && keyboardAccessibilityOverridesEnabled
        self.keyboardAccessibilityOverridesEnabled = keyboardAccessibilityOverridesEnabled
        if keyboardOverrideJustEnabled {
            clearFocusForVisiblePanels()
        }
        let anyVisibleRequested =
            showHypnograms || showSources || showNewClips || showOutputSettings || showComposition || showEffects || showPlayerControls
        let shouldStartAutoHidden =
            autoHideWindows && anyVisibleRequested && !hasInitializedVisiblePanelPresentation

        guard let parentWindow else {
            stopAutoHideMonitoring()
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
            stopAutoHideMonitoring()
            hideAllPanels()
            return
        }

        configureParentWindowForFullScreen(parentWindow)
        updateAutoHideMonitoring(enabled: autoHideWindows, startHidden: shouldStartAutoHidden)

        syncPanel(
            kind: .hypnograms,
            visible: showHypnograms,
            content: hypnogramsContent,
            parentWindow: parentWindow,
            suppressVisibilityActivity: shouldStartAutoHidden
        )
        syncPanel(
            kind: .sources,
            visible: showSources,
            content: sourcesContent,
            parentWindow: parentWindow,
            suppressVisibilityActivity: shouldStartAutoHidden
        )
        syncPanel(
            kind: .newClips,
            visible: showNewClips,
            content: newClipsContent,
            parentWindow: parentWindow,
            suppressVisibilityActivity: shouldStartAutoHidden
        )
        syncPanel(
            kind: .outputSettings,
            visible: showOutputSettings,
            content: outputSettingsContent,
            parentWindow: parentWindow,
            suppressVisibilityActivity: shouldStartAutoHidden
        )
        syncPanel(
            kind: .composition,
            visible: showComposition,
            content: compositionContent,
            parentWindow: parentWindow,
            suppressVisibilityActivity: shouldStartAutoHidden
        )
        syncPanel(
            kind: .effects,
            visible: showEffects,
            content: effectsContent,
            parentWindow: parentWindow,
            suppressVisibilityActivity: shouldStartAutoHidden
        )
        syncPanel(
            kind: .playerControls,
            visible: showPlayerControls,
            content: playerControlsContent,
            parentWindow: parentWindow,
            suppressVisibilityActivity: shouldStartAutoHidden,
            layoutSignature: playerControlsLayoutSignature
        )

        if anyVisibleRequested {
            hasInitializedVisiblePanelPresentation = true
        }
    }

    func teardown() {
        stopAutoHideMonitoring()
        hideAllPanels()
        detachFromCurrentParent()
        removeParentCloseObserver()
        panels.values.forEach { $0.panel.close() }
        panels.removeAll()
        panelLayoutSignatures.removeAll()
        requestedVisibility.removeAll()
        hasInitializedVisiblePanelPresentation = false
        parentWindow = nil
    }

    private func syncPanel(
        kind: WindowKind,
        visible: Bool,
        content: AnyView,
        parentWindow: NSWindow,
        suppressVisibilityActivity: Bool,
        layoutSignature: Int? = nil
    ) {
        let previousVisibility = requestedVisibility[kind] ?? false
        requestedVisibility[kind] = visible

        if visible && !previousVisibility && !suppressVisibilityActivity {
            noteActivity()
        }

        if visible {
            let managed = ensurePanel(kind: kind, parentWindow: parentWindow, content: content)
            managed.host.rootView = content
            let shouldApplySizing: Bool
            if let layoutSignature {
                let previousSignature = panelLayoutSignatures[kind]
                shouldApplySizing = previousSignature != layoutSignature
                panelLayoutSignatures[kind] = layoutSignature
            } else {
                shouldApplySizing = true
            }

            if shouldApplySizing {
                applySizing(for: kind, managed: managed)
            }

            if panelsAutoHidden {
                if managed.panel.parent === parentWindow {
                    parentWindow.removeChildWindow(managed.panel)
                }
                managed.panel.orderOut(nil)
            } else {
                if managed.panel.parent == nil {
                    parentWindow.addChildWindow(managed.panel, ordered: .above)
                }
                if !managed.panel.isVisible {
                    managed.panel.orderFront(nil)
                    clearInitialFocusIfNeeded(for: managed.panel)
                }
            }
        } else if let managed = panels[kind] {
            panelLayoutSignatures[kind] = nil
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
            styleMask: kind.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.title = kind.title
        if kind.usesTitlebarChrome {
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
        }
        panel.isMovableByWindowBackground = kind.allowsBackgroundDragging
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.level = parentWindow.level
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.backgroundColor = kind.backgroundColor
        panel.isOpaque = false
        panel.hasShadow = kind.hasShadow
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.setFrameAutosaveName(kind.autosaveName)
        _ = panel.setFrameUsingName(kind.autosaveName, force: false)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.initialFirstResponder = nil
        if kind.usesTitlebarChrome {
            installTitleAccessory(for: panel, title: kind.title)
        }
        panel.onUserInteraction = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.noteActivity()
            self.bringToFront(panel)
        }
        panel.onCloseRequest = { [weak self, weak panel] in
            guard let self else { return }
            self.handleCloseRequest(for: kind, panel: panel)
        }

        let host = NSHostingController(rootView: content)
        host.view.appearance = NSAppearance(named: .darkAqua)
        panel.contentViewController = host
        panel.orderOut(nil)

        let managed = ManagedPanel(panel: panel, host: host)
        panels[kind] = managed
        return managed
    }

    private func clearInitialFocusIfNeeded(for panel: NSWindow) {
        guard keyboardAccessibilityOverridesEnabled else { return }
        DispatchQueue.main.async {
            guard panel.isVisible else { return }
            panel.makeFirstResponder(nil)
        }
    }

    private func clearFocusForVisiblePanels() {
        for managed in panels.values where managed.panel.isVisible {
            clearInitialFocusIfNeeded(for: managed.panel)
        }
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
        let currentContentWidth = max(1, panel.contentLayoutRect.width)
        let clampedWidth = min(max(currentContentWidth, kind.minSize.width), kind.maxWidth)
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
            let targetHeight = measuredHeight

            applyContentConstraints(
                panel: panel,
                minContentSize: CGSize(width: kind.minSize.width, height: targetHeight),
                maxContentSize: CGSize(width: kind.maxWidth, height: targetHeight)
            )
            resizePanel(
                panel,
                toContentSize: CGSize(width: clampedWidth, height: targetHeight),
                pinTopEdge: kind != .playerControls
            )
        } else {
            applyContentConstraints(
                panel: panel,
                minContentSize: kind.minSize,
                maxContentSize: CGSize(width: kind.maxWidth, height: .greatestFiniteMagnitude)
            )

            if abs(panel.contentLayoutRect.width - clampedWidth) > 1 {
                resizePanel(
                    panel,
                    toContentSize: CGSize(
                        width: clampedWidth,
                        height: max(kind.minSize.height, panel.contentLayoutRect.height)
                    ),
                    pinTopEdge: kind != .playerControls
                )
            }
        }

        if !kind.isResizable {
            panel.minSize = panel.frame.size
            panel.maxSize = panel.frame.size
        }
    }

    private func applyContentConstraints(
        panel: NSPanel,
        minContentSize: CGSize,
        maxContentSize: CGSize
    ) {
        panel.contentMinSize = minContentSize
        panel.contentMaxSize = maxContentSize

        let minFrameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: minContentSize)).size
        panel.minSize = minFrameSize

        if maxContentSize.height.isFinite {
            let maxFrameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: maxContentSize)).size
            panel.maxSize = maxFrameSize
        } else {
            let referenceContentHeight = max(max(minContentSize.height, panel.contentLayoutRect.height), 1)
            let maxFrameWidth = panel.frameRect(
                forContentRect: NSRect(
                    origin: .zero,
                    size: CGSize(width: maxContentSize.width, height: referenceContentHeight)
                )
            ).width
            panel.maxSize = CGSize(width: maxFrameWidth, height: .greatestFiniteMagnitude)
        }
    }

    private func resizePanel(
        _ panel: NSPanel,
        toContentSize contentSize: CGSize,
        pinTopEdge: Bool
    ) {
        let startingFrame = panel.frame
        let currentContentSize = panel.contentLayoutRect.size
        let sizeChanged =
            abs(currentContentSize.width - contentSize.width) > 1 ||
            abs(currentContentSize.height - contentSize.height) > 1

        if sizeChanged {
            panel.setContentSize(contentSize)
        }

        let targetOrigin: CGPoint
        if pinTopEdge {
            targetOrigin = CGPoint(
                x: startingFrame.origin.x,
                y: startingFrame.maxY - panel.frame.height
            )
        } else {
            targetOrigin = CGPoint(
                x: startingFrame.origin.x,
                y: startingFrame.origin.y
            )
        }

        let originChanged =
            abs(panel.frame.origin.x - targetOrigin.x) > 1 ||
            abs(panel.frame.origin.y - targetOrigin.y) > 1

        if originChanged {
            panel.setFrameOrigin(targetOrigin)
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

    private func updateAutoHideMonitoring(enabled: Bool, startHidden: Bool) {
        guard autoHideWindowsEnabled != enabled else {
            if enabled {
                startAutoHideMonitoringIfNeeded()
                if startHidden {
                    setPanelsAutoHidden(true)
                } else {
                    noteActivity()
                }
            }
            return
        }

        autoHideWindowsEnabled = enabled
        if enabled {
            startAutoHideMonitoringIfNeeded()
            if startHidden {
                setPanelsAutoHidden(true)
            } else {
                noteActivity()
            }
        } else {
            autoHideTimer?.invalidate()
            autoHideTimer = nil
        }
    }

    func hidePanelsForCanvasInteraction() {
        togglePanelsVisibility()
    }

    func hidePanelsNow() {
        togglePanelsVisibility()
    }

    func showPanelsNow() {
        guard panelsAutoHidden else { return }
        setPanelsAutoHidden(false)
        noteActivity()
        if autoHideWindowsEnabled {
            startAutoHideMonitoringIfNeeded()
        }
    }

    func togglePanelsVisibility() {
        if panelsAutoHidden {
            setPanelsAutoHidden(false)
            noteActivity()
            if autoHideWindowsEnabled {
                startAutoHideMonitoringIfNeeded()
            }
        } else {
            setPanelsAutoHidden(true)
            lastMouseLocation = NSEvent.mouseLocation
            lastActivityTime = CFAbsoluteTimeGetCurrent()
        }
    }

    private func startAutoHideMonitoringIfNeeded() {
        guard autoHideTimer == nil else { return }

        lastMouseLocation = NSEvent.mouseLocation
        lastActivityTime = CFAbsoluteTimeGetCurrent()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollAutoHideState()
            }
        }
        if let autoHideTimer {
            RunLoop.main.add(autoHideTimer, forMode: .common)
        }
    }

    private func stopAutoHideMonitoring() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        autoHideWindowsEnabled = false
        panelsAutoHidden = false
    }

    private func noteActivity() {
        lastMouseLocation = NSEvent.mouseLocation
        lastActivityTime = CFAbsoluteTimeGetCurrent()
    }

    private func pollAutoHideState() {
        guard autoHideWindowsEnabled else { return }

        guard NSApp.isActive else {
            return
        }

        let location = NSEvent.mouseLocation
        if location.x != lastMouseLocation.x || location.y != lastMouseLocation.y {
            lastMouseLocation = location
            lastActivityTime = CFAbsoluteTimeGetCurrent()
            return
        }

        if panelsAutoHidden {
            return
        }

        let shouldHide = (CFAbsoluteTimeGetCurrent() - lastActivityTime) >= autoHideIdleSeconds
        setPanelsAutoHidden(shouldHide)
    }

    private func setPanelsAutoHidden(_ hidden: Bool) {
        guard panelsAutoHidden != hidden else { return }
        panelsAutoHidden = hidden
        onPanelsAutoHiddenChanged?(hidden)

        for (kind, managed) in panels where requestedVisibility[kind] == true {
            if hidden {
                managed.panel.orderOut(nil)
            } else if let parentWindow {
                if managed.panel.parent == nil {
                    parentWindow.addChildWindow(managed.panel, ordered: .above)
                }
                managed.panel.orderFront(nil)
            }
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
        stopAutoHideMonitoring()
        hideAllPanels()
        detachFromCurrentParent()
        parentWindow = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let kind = kind(for: sender) else { return true }
        handleCloseRequest(for: kind, panel: sender as? NSPanel)
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard keyboardAccessibilityOverridesEnabled else { return }
        guard let window = notification.object as? NSWindow else { return }
        guard kind(for: window) != nil else { return }
        DispatchQueue.main.async {
            window.makeFirstResponder(nil)
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let kind = kind(for: sender) else { return frameSize }

        let proposedContentRect = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize))
        let clampedContentWidth = min(max(proposedContentRect.width, kind.minSize.width), kind.maxWidth)

        let targetContentHeight: CGFloat
        if kind.shouldFitHeightToContent {
            let currentContentHeight = sender.contentRect(forFrameRect: sender.frame).height
            targetContentHeight = max(kind.minSize.height, currentContentHeight)
        } else {
            targetContentHeight = max(kind.minSize.height, proposedContentRect.height)
        }

        return sender.frameRect(
            forContentRect: NSRect(
                origin: .zero,
                size: CGSize(width: clampedContentWidth, height: targetContentHeight)
            )
        ).size
    }
}
