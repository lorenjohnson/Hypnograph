import SwiftUI
import AVFoundation
import CoreMedia
import CoreGraphics
import Combine

// Simple no-op renderer since Divine is view-only.
final class DivineNoopRenderer: HypnogramRenderer {
    func enqueue(recipe: HypnogramRecipe, completion: @escaping (Result<URL, Error>) -> Void) {
        completion(.failure(NSError(
            domain: "DivineMode",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Rendering not supported for Divine mode."]
        )))
    }
}

/// Tarot-style stills mode with drag-and-drop cards from a bottom-right deck.
final class DivineMode: ObservableObject, HypnographMode {

    // MARK: - Dependencies / core state

    private let state: HypnogramState
    let renderQueue: RenderQueue

    let cardManager: DivineCardManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - View transform (zoom + pan) exposed to the view

    @Published var sceneScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero

    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 3.0
    private let zoomStep: CGFloat = 1.1

    init(state: HypnogramState) {
        self.state = state
        self.renderQueue = RenderQueue(renderer: DivineNoopRenderer())
        self.cardManager = DivineCardManager(state: state)

        // Bridge cardManager changes into DivineMode's objectWillChange
        cardManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Exposed state

    var cards: [DivineCard] {
        cardManager.cards
    }

    // MARK: - HypnographMode basics

    var currentSourceIndex: Int { cardManager.currentIndex }
    var isSoloActive: Bool { false }
    var soloIndicatorText: String? { nil }

    func makeDisplayView(state: HypnogramState, renderQueue: RenderQueue) -> AnyView {
        // Build bindings manually because we're not in a View context.
        let sceneScaleBinding = Binding<CGFloat>(
            get: { [weak self] in
                self?.sceneScale ?? 1.0
            },
            set: { [weak self] newValue in
                self?.sceneScale = newValue
            }
        )

        let panOffsetBinding = Binding<CGSize>(
            get: { [weak self] in
                self?.panOffset ?? .zero
            },
            set: { [weak self] newValue in
                self?.panOffset = newValue
            }
        )

        return AnyView(
            DivineView(
                cards: cardManager.cards,
                onTap: { [weak self] id in
                    self?.cardManager.handleTap(id: id)
                },
                onLongPress: { [weak self] id in
                    self?.cardManager.handleLongPress(id: id)
                },
                onDragChanged: { [weak self] id, translation in
                    self?.cardManager.updateDrag(id: id, translation: translation)
                },
                onDragEnded: { [weak self] id, translation in
                    self?.cardManager.endDrag(id: id, translation: translation)
                },
                onLayoutUpdate: { [weak self] viewport, cardSize in
                    self?.cardManager.updateLayout(viewport: viewport, cardSize: cardSize)
                },
                playerProvider: { [weak self] id in
                    self?.cardManager.player(forID: id)
                },
                sceneScale: sceneScaleBinding,
                panOffset: panOffsetBinding
            )
        )
    }

    func hudItems(state: HypnogramState, renderQueue: RenderQueue) -> [HUDItem] {
        [
            .text("Space: Clear table", order: 27),
        ]
    }

    func compositionCommands() -> [ModeCommand] {
        [
            ModeCommand(
                title: "Zoom In",
                key: "=",
                modifiers: [.command]
            ) { [weak self] in
                self?.zoomInStep()
            },
            ModeCommand(
                title: "Zoom Out",
                key: "-",
                modifiers: [.command]
            ) { [weak self] in
                self?.zoomOutStep()
            },
            ModeCommand(
                title: "Reset View",
                key: "0",
                modifiers: [.command]
            ) { [weak self] in
                self?.resetViewTransform()
            }
        ]
    }

    func sourceCommands() -> [ModeCommand] { [] }

    // MARK: - Lifecycle

    func new() {
        clearTable()
        cardManager.addCardAtRandom()
    }

    func save() {
        print("DivineMode: save not supported.")
    }

    // MARK: - Source navigation

    func addSource() {
        cardManager.addCardAtRandom()
    }

    func nextSource() {
        cardManager.nextSource()
    }

    func previousSource() {
        cardManager.previousSource()
    }

    func selectSource(index: Int) {
        cardManager.selectSource(index: index)
    }

    // MARK: - Candidate / selection

    func nextCandidate() {
        // For Divine, "next candidate" = draw another card.
        cardManager.addCardAtRandom()
    }

    func acceptCandidate() {
        // No-op for Divine; interactions happen via tap/press.
    }

    func deleteCurrentSource() {
        cardManager.deleteCurrent()
    }

    func excludeCurrentSource() {
        // Divine mode doesn’t use the same "exclude" semantics as montage.
    }

    func redeal() {
        clearTable()
    }

    // MARK: - Effects / misc

    func cycleEffect() { }

    func toggleHUD() {
        state.toggleHUD()
    }

    func toggleSolo() { }

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
        clearTable()
    }

    func cycleGlobalEffect() {
        state.renderHooks.cycleGlobalEffect()
    }

    func cycleSourceEffect() {
        state.renderHooks.cycleSourceEffect(for: currentSourceIndex)
    }

    func clearAllEffects() {
        state.renderHooks.setGlobalEffect(nil)
        state.renderHooks.setSourceEffect(nil, for: currentSourceIndex)
    }

    var globalEffectName: String {
        state.renderHooks.globalEffectName
    }

    var sourceEffectName: String {
        state.renderHooks.sourceEffectName(for: currentSourceIndex)
    }

    func selectOrToggleSolo(index: Int) {
        selectSource(index: index)
    }

    // MARK: - View transform helpers (zoom + pan)

    private func zoomInStep() {
        let newScale = min(sceneScale * zoomStep, maxZoom)
        sceneScale = newScale
    }

    private func zoomOutStep() {
        let newScale = max(sceneScale / zoomStep, minZoom)
        sceneScale = newScale
    }

    private func resetViewTransform() {
        sceneScale = 1.0
        panOffset = .zero
    }

    // MARK: - Internal helpers

    private func clearTable() {
        cardManager.reset()
        resetViewTransform()
    }
}
