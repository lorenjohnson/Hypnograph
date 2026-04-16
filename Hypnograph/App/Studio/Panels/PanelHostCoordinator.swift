//
//  PanelHostCoordinator.swift
//  Hypnograph
//

import SwiftUI
import AppKit

private enum PanelKind {
    case hypnograms
    case newCompositions
    case properties
    case effects
    case playerControls

    var title: String {
        switch self {
        case .hypnograms: return "Hypnograms"
        case .newCompositions: return "New Compositions"
        case .properties: return "Properties"
        case .effects: return "Effect Chains"
        case .playerControls: return "Player Controls"
        }
    }

    var panelStateID: String {
        switch self {
        case .hypnograms: return "hypnogramsPanel"
        case .newCompositions: return "newCompositionsPanel"
        case .properties: return "propertiesPanel"
        case .effects: return "effectsPanel"
        case .playerControls: return "playerControlsPanel"
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .hypnograms: return CGSize(width: 420, height: 520)
        case .newCompositions: return CGSize(width: 360, height: 620)
        case .properties: return CGSize(width: 360, height: 720)
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

    var fixedContentWidth: CGFloat? {
        switch self {
        case .newCompositions, .properties:
            return defaultSize.width
        default:
            return nil
        }
    }

    var minSize: CGSize {
        switch self {
        case .hypnograms: return CGSize(width: 360, height: 320)
        case .newCompositions: return CGSize(width: defaultSize.width, height: 120)
        case .properties: return CGSize(width: defaultSize.width, height: 120)
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
        case .properties, .effects, .playerControls:
            return false
        default:
            return true
        }
    }

    var defaultOrigin: (NSRect, CGSize) -> CGPoint {
        switch self {
        case .hypnograms:
            return { parentFrame, size in
                CGPoint(x: parentFrame.minX - size.width - 16, y: parentFrame.maxY - size.height - 420)
            }
        case .newCompositions:
            return { parentFrame, size in
                CGPoint(x: parentFrame.minX - size.width - 16, y: parentFrame.maxY - size.height - 36)
            }
        case .properties:
            return { parentFrame, size in
                CGPoint(x: parentFrame.maxX + 16, y: parentFrame.maxY - size.height)
            }
        case .effects:
            return { parentFrame, size in
                CGPoint(x: parentFrame.maxX + 16, y: parentFrame.maxY - size.height)
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

    var styleMask: NSWindow.StyleMask {
        var mask: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView, .utilityWindow]
        if isResizable {
            mask.insert(.resizable)
        }
        return mask
    }

    var isResizable: Bool {
        switch self {
        case .hypnograms, .effects:
            return true
        default:
            return false
        }
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

    var shouldRefreshRootViewOnSync: Bool {
        switch self {
        case .hypnograms, .newCompositions, .properties, .effects, .playerControls:
            return false
        }
    }
}

private final class ChildPanel: NSPanel {
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

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class PanelContentController: NSViewController {
    private let kind: PanelKind
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private let documentView = FlippedDocumentView()
    private let scrollView = NSScrollView()

    var onLayoutPass: (() -> Void)?
    var onLayoutInvalidationRequest: ((Bool) -> Void)?

    init(kind: PanelKind, content: AnyView) {
        self.kind = kind
        super.init(nibName: nil, bundle: nil)
        setRootView(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = false

        hostingView.appearance = NSAppearance(named: .darkAqua)

        if kind.shouldFitHeightToContent {
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            documentView.translatesAutoresizingMaskIntoConstraints = false
            documentView.addSubview(hostingView)
            scrollView.documentView = documentView
            container.addSubview(scrollView)
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor)
            ])
        } else {
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: container.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }

        view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateHostedLayout()
        onLayoutPass?()
    }

    func setRootView(_ content: AnyView) {
        let invalidationAwareContent = AnyView(
            content.environment(
                \.panelLayoutInvalidator,
                 PanelLayoutInvalidator(
                    invalidate: { [weak self] resetScrollToTop in
                        self?.onLayoutInvalidationRequest?(resetScrollToTop)
                    }
                 )
            )
        )
        if kind.shouldFitHeightToContent {
            hostingView.rootView = AnyView(invalidationAwareContent.fixedSize(horizontal: false, vertical: true))
        } else {
            hostingView.rootView = invalidationAwareContent
        }
        updateHostedLayout()
    }

    func measuredContentHeight(for width: CGFloat) -> CGFloat {
        updateHostedLayout(forcedWidth: width)
        hostingView.layoutSubtreeIfNeeded()
        return max(hostingView.fittingSize.height, hostingView.frame.height)
    }

    private func updateHostedLayout(forcedWidth: CGFloat? = nil) {
        guard kind.shouldFitHeightToContent else { return }

        let targetWidth = max(1, forcedWidth ?? scrollView.contentSize.width)
        let currentHeight = max(1, hostingView.frame.height)
        if abs(hostingView.frame.width - targetWidth) > 0.5 {
            hostingView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: currentHeight)
        }

        hostingView.layoutSubtreeIfNeeded()
        let fittingHeight = max(1, hostingView.fittingSize.height)
        let documentHeight = max(fittingHeight, scrollView.contentSize.height)
        if abs(hostingView.frame.height - fittingHeight) > 0.5 || abs(hostingView.frame.width - targetWidth) > 0.5 {
            hostingView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: fittingHeight)
        }
        if abs(documentView.frame.width - targetWidth) > 0.5 || abs(documentView.frame.height - documentHeight) > 0.5 {
            documentView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: documentHeight)
        }
    }

    func resetScrollPositionToTop() {
        guard kind.shouldFitHeightToContent else { return }
        let clipView = scrollView.contentView
        clipView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(clipView)
    }
}

@MainActor
final class PanelHostCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    private struct ManagedPanel {
        let panel: ChildPanel
        let host: PanelContentController
    }

    private weak var parentWindow: NSWindow?
    private var panels: [PanelKind: ManagedPanel] = [:]
    private var requestedVisibility: [PanelKind: Bool] = [:]
    private var parentCloseObserver: NSObjectProtocol?
    private var onPanelVisibilityChanged: ((String, Bool) -> Void)?
    private var onPanelFrameChanged: ((String, CGRect) -> Void)?
    private var onPanelOrderChanged: (([String]) -> Void)?
    private var onPanelsAutoHiddenChanged: ((Bool) -> Void)?
    private var storedPanelFrames: [String: CGRect] = [:]
    private var panelOrder: [String] = []
    private var needsPanelOrderRestore = false
    private var autoHidePanelsEnabled = false
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
        showNewCompositions: Bool,
        showProperties: Bool,
        showEffects: Bool,
        showPlayerControls: Bool,
        expectedParentFullScreen: Bool,
        panelFrames: [String: CGRect],
        panelOrder: [String],
        panelOpacity: Double,
        autoHidePanels: Bool,
        keyboardAccessibilityOverridesEnabled: Bool,
        onPanelVisibilityChanged: @escaping (String, Bool) -> Void,
        onPanelFrameChanged: @escaping (String, CGRect) -> Void,
        onPanelOrderChanged: @escaping ([String]) -> Void,
        onPanelsAutoHiddenChanged: @escaping (Bool) -> Void,
        hypnogramsContent: AnyView,
        newCompositionsContent: AnyView,
        propertiesContent: AnyView,
        effectsContent: AnyView,
        playerControlsContent: AnyView
    ) {
        if self.panelOrder != panelOrder {
            needsPanelOrderRestore = true
        }
        self.onPanelVisibilityChanged = onPanelVisibilityChanged
        self.onPanelFrameChanged = onPanelFrameChanged
        self.onPanelOrderChanged = onPanelOrderChanged
        self.onPanelsAutoHiddenChanged = onPanelsAutoHiddenChanged
        self.storedPanelFrames = panelFrames
        self.panelOrder = panelOrder
        onPanelsAutoHiddenChanged(panelsAutoHidden)
        let opacity = min(max(panelOpacity, 0.32), 0.92)
        let keyboardOverrideJustEnabled = !self.keyboardAccessibilityOverridesEnabled && keyboardAccessibilityOverridesEnabled
        self.keyboardAccessibilityOverridesEnabled = keyboardAccessibilityOverridesEnabled
        if keyboardOverrideJustEnabled {
            clearFocusForVisiblePanels()
        }
        let anyVisibleRequested =
            showHypnograms || showNewCompositions || showProperties || showEffects || showPlayerControls
        let shouldStartAutoHidden =
            autoHidePanels && anyVisibleRequested && !hasInitializedVisiblePanelPresentation

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

        let parentIsFullScreen = parentWindow.styleMask.contains(.fullScreen)
        guard parentIsFullScreen == expectedParentFullScreen else {
            stopAutoHideMonitoring()
            hideAllPanels()
            return
        }

        updateAutoHideMonitoring(enabled: autoHidePanels, startHidden: shouldStartAutoHidden)

        syncPanel(
            kind: .hypnograms,
            visible: showHypnograms,
            opacity: opacity,
            content: hypnogramsContent,
            parentWindow: parentWindow,
            suppressVisibilityActivity: shouldStartAutoHidden
        )
        syncPanel(
            kind: .newCompositions,
            visible: showNewCompositions,
            opacity: opacity,
            content: newCompositionsContent,
            parentWindow: parentWindow,
            suppressVisibilityActivity: shouldStartAutoHidden
        )
        syncPanel(
            kind: .properties,
            visible: showProperties,
            opacity: opacity,
            content: propertiesContent,
            parentWindow: parentWindow,
            suppressVisibilityActivity: shouldStartAutoHidden
        )
        syncPanel(
            kind: .effects,
            visible: showEffects,
            opacity: opacity,
            content: effectsContent,
            parentWindow: parentWindow,
            suppressVisibilityActivity: shouldStartAutoHidden
        )
        syncPanel(
            kind: .playerControls,
            visible: showPlayerControls,
            opacity: opacity,
            content: playerControlsContent,
            parentWindow: parentWindow,
            suppressVisibilityActivity: shouldStartAutoHidden
        )

        if anyVisibleRequested {
            hasInitializedVisiblePanelPresentation = true
            if needsPanelOrderRestore {
                restorePanelOrderIfNeeded()
                needsPanelOrderRestore = false
            }
        }
    }

    func teardown() {
        stopAutoHideMonitoring()
        hideAllPanels()
        detachFromCurrentParent()
        removeParentCloseObserver()
        panels.values.forEach { $0.panel.close() }
        panels.removeAll()
        requestedVisibility.removeAll()
        hasInitializedVisiblePanelPresentation = false
        parentWindow = nil
    }

    private func syncPanel(
        kind: PanelKind,
        visible: Bool,
        opacity: Double,
        content: AnyView,
        parentWindow: NSWindow,
        suppressVisibilityActivity: Bool
    ) {
        let previousVisibility = requestedVisibility[kind] ?? false
        requestedVisibility[kind] = visible
        if previousVisibility != visible {
            needsPanelOrderRestore = true
        }

        if visible && !previousVisibility && !suppressVisibilityActivity {
            noteActivity()
        }

        if visible {
            let managed = ensurePanel(kind: kind, parentWindow: parentWindow, content: content)
            if kind.shouldRefreshRootViewOnSync {
                managed.host.setRootView(content)
            }
            managed.panel.alphaValue = opacity
            applySizing(for: kind, managed: managed)

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
            if managed.panel.parent === parentWindow {
                parentWindow.removeChildWindow(managed.panel)
            }
            managed.panel.orderOut(nil)
        }
    }

    private func ensurePanel(kind: PanelKind, parentWindow: NSWindow, content: AnyView) -> ManagedPanel {
        if let existing = panels[kind] {
            return existing
        }

        let frame = defaultFrame(kind: kind, parentWindow: parentWindow)
        let panel = ChildPanel(
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

        let host = PanelContentController(kind: kind, content: content)
        host.onLayoutPass = { [weak self, weak panel] in
            guard let self, let panel, let kind = self.kind(for: panel) else { return }
            self.handleHostedContentLayout(for: kind)
        }
        host.onLayoutInvalidationRequest = { [weak self, weak panel] resetScrollToTop in
            guard let self, let panel, let kind = self.kind(for: panel) else { return }
            self.handleExplicitLayoutInvalidation(for: kind, resetScrollToTop: resetScrollToTop)
        }
        panel.contentViewController = host
        panel.orderOut(nil)

        if let savedFrame = storedPanelFrames[kind.panelStateID] {
            panel.setFrame(savedFrame, display: false)
        }

        let managed = ManagedPanel(
            panel: panel,
            host: host
        )
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

    private func applySizing(for kind: PanelKind, managed: ManagedPanel) {
        let panel = managed.panel
        let currentContentWidth = max(1, panel.contentRect(forFrameRect: panel.frame).width)
        let clampedWidth = if let fixedContentWidth = kind.fixedContentWidth {
            fixedContentWidth
        } else {
            min(max(currentContentWidth, kind.minSize.width), kind.maxWidth)
        }
        let maxInitialHeight = maximumInitialHeight(for: panel)

        if kind.shouldFitHeightToContent {
            let contentHeight = managed.host.measuredContentHeight(for: clampedWidth)
            let layoutExclusionHeight = obscuredLayoutHeight(for: panel)
            let measuredHeight = min(
                max(
                    kind.minSize.height,
                    contentHeight + layoutExclusionHeight
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

            if abs(panel.contentRect(forFrameRect: panel.frame).width - clampedWidth) > 1 {
                resizePanel(
                    panel,
                    toContentSize: CGSize(
                        width: clampedWidth,
                        height: max(kind.minSize.height, panel.contentRect(forFrameRect: panel.frame).height)
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
            let referenceContentHeight = max(max(minContentSize.height, panel.contentRect(forFrameRect: panel.frame).height), 1)
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
        let targetFrameSize = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size

        let targetOrigin: CGPoint
        if pinTopEdge {
            targetOrigin = CGPoint(
                x: startingFrame.origin.x,
                y: startingFrame.maxY - targetFrameSize.height
            )
        } else {
            targetOrigin = CGPoint(
                x: startingFrame.origin.x,
                y: startingFrame.origin.y
            )
        }

        let targetFrame = NSRect(origin: targetOrigin, size: targetFrameSize)
        let frameChanged =
            abs(startingFrame.origin.x - targetFrame.origin.x) > 1 ||
            abs(startingFrame.origin.y - targetFrame.origin.y) > 1 ||
            abs(startingFrame.size.width - targetFrame.size.width) > 1 ||
            abs(startingFrame.size.height - targetFrame.size.height) > 1

        if frameChanged {
            panel.setFrame(targetFrame, display: false)
        }
    }

    private func maximumInitialHeight(for panel: NSPanel) -> CGFloat {
        let visibleHeight = panel.screen?.visibleFrame.height
            ?? parentWindow?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 900

        return max(320, visibleHeight - 140)
    }

    private func obscuredLayoutHeight(for panel: NSPanel) -> CGFloat {
        let contentRectHeight = panel.contentRect(forFrameRect: panel.frame).height
        let visibleLayoutHeight = panel.contentLayoutRect.height
        return max(0, contentRectHeight - visibleLayoutHeight)
    }

    private func configureParentWindowForFullScreen(_ window: NSWindow) {
        var behavior = window.collectionBehavior
        if !behavior.contains(.fullScreenPrimary) {
            behavior.insert(.fullScreenPrimary)
            window.collectionBehavior = behavior
        }
    }

    private func defaultFrame(kind: PanelKind, parentWindow: NSWindow) -> NSRect {
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
        guard autoHidePanelsEnabled != enabled else {
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

        autoHidePanelsEnabled = enabled
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
        if autoHidePanelsEnabled {
            startAutoHideMonitoringIfNeeded()
        }
    }

    func togglePanelsVisibility() {
        if panelsAutoHidden {
            setPanelsAutoHidden(false)
            noteActivity()
            if autoHidePanelsEnabled {
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
        autoHidePanelsEnabled = false
        panelsAutoHidden = false
    }

    private func noteActivity() {
        lastMouseLocation = NSEvent.mouseLocation
        lastActivityTime = CFAbsoluteTimeGetCurrent()
    }

    private func pollAutoHideState() {
        guard autoHidePanelsEnabled else { return }

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

        if !hidden {
            needsPanelOrderRestore = true
            restorePanelOrderIfNeeded()
        }
    }

    private func handleCloseRequest(for kind: PanelKind, panel: NSPanel?) {
        if let panel, let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        panel?.orderOut(nil)
        onPanelVisibilityChanged?(kind.panelStateID, false)
    }

    private func bringToFront(_ panel: NSPanel) {
        if let parentWindow, panel.parent === parentWindow {
            parentWindow.removeChildWindow(panel)
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
        if let kind = kind(for: panel) {
            notePanelBroughtToFront(kind.panelStateID)
        }
    }

    private func kind(for panel: NSWindow) -> PanelKind? {
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
        guard let window = notification.object as? NSWindow else { return }
        guard let kind = kind(for: window) else { return }
        notePanelBroughtToFront(kind.panelStateID)
        guard keyboardAccessibilityOverridesEnabled else { return }
        DispatchQueue.main.async {
            window.makeFirstResponder(nil)
        }
    }

    func windowDidMove(_ notification: Notification) {
        persistPanelFrame(from: notification)
    }

    func windowDidResize(_ notification: Notification) {
        persistPanelFrame(from: notification)
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

    private func persistPanelFrame(from notification: Notification) {
        guard let panel = notification.object as? NSWindow else { return }
        guard let kind = kind(for: panel) else { return }
        let panelID = kind.panelStateID
        let frame = panel.frame
        DispatchQueue.main.async { [weak self] in
            self?.onPanelFrameChanged?(panelID, frame)
        }
    }

    private func handleHostedContentLayout(for kind: PanelKind) {
        guard kind.shouldFitHeightToContent else { return }
        guard let managed = panels[kind] else { return }
        applySizing(for: kind, managed: managed)
    }

    private func handleExplicitLayoutInvalidation(for kind: PanelKind, resetScrollToTop: Bool = false) {
        guard kind.shouldFitHeightToContent else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let managed = self.panels[kind] else { return }
            self.applySizing(for: kind, managed: managed)
            if resetScrollToTop {
                DispatchQueue.main.async {
                    managed.host.resetScrollPositionToTop()
                }
            }
        }
    }

    private func notePanelBroughtToFront(_ windowID: String) {
        var nextOrder = panelOrder.filter { $0 != windowID }
        nextOrder.append(windowID)
        guard nextOrder != panelOrder else { return }
        panelOrder = nextOrder
        DispatchQueue.main.async { [weak self] in
            self?.onPanelOrderChanged?(nextOrder)
        }
    }

    private func restorePanelOrderIfNeeded() {
        guard !panelOrder.isEmpty, let parentWindow else {
            return
        }

        let visiblePanels: [(windowID: String, panel: ChildPanel)] = panels.compactMap { entry in
            let (kind, managed) = entry
            guard requestedVisibility[kind] == true, managed.panel.isVisible else {
                return nil
            }
            return (kind.panelStateID, managed.panel)
        }

        guard !visiblePanels.isEmpty else { return }

        let rankedPanels = visiblePanels.sorted { lhs, rhs in
            let lhsRank = panelOrder.firstIndex(of: lhs.windowID) ?? Int.max
            let rhsRank = panelOrder.firstIndex(of: rhs.windowID) ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.windowID < rhs.windowID
        }

        for managed in rankedPanels {
            if managed.panel.parent === parentWindow {
                parentWindow.removeChildWindow(managed.panel)
                parentWindow.addChildWindow(managed.panel, ordered: .above)
            }
            managed.panel.orderFront(nil)
        }
    }
}
