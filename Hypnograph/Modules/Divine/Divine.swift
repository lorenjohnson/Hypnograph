//
//  Divine.swift
//  Hypnograph
//
//  Divine feature: Tarot-style stills with drag-and-drop cards.
//

import SwiftUI
import AVFoundation
import CoreMedia
import CoreGraphics

/// Tarot-style stills with drag-and-drop cards.
@MainActor
final class Divine: ObservableObject {
    let state: HypnographState
    let renderQueue: RenderQueue

    let cardManager: DivineCardManager

    // MARK: - View transform (zoom + pan) exposed to the view

    @Published var sceneScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero

    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 3.0
    private let zoomStep: CGFloat = 1.1

    init(state: HypnographState, renderQueue: RenderQueue) {
        self.state = state
        self.renderQueue = renderQueue
        self.cardManager = DivineCardManager(state: state)
    }

    // MARK: - Display

    func makeDisplayView() -> AnyView {
        // Ensure at least one card exists (deferred from init to use correct per-mode library)
        if cardManager.cards.isEmpty {
            cardManager.addCardAtOffsetAtCenter()
        }

        return AnyView(
            DivineView(
                mode: self,
                cardManager: cardManager,
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
                onBackgroundDoubleTap: { [weak self] offset in
                    self?.cardManager.addCardAtOffset(offset: offset)
                },
                playerProvider: { [weak self] id in
                    self?.cardManager.player(forID: id)
                },
                minZoom: minZoom,
                maxZoom: maxZoom
            )
        )
    }

    func hudItems() -> [HUDItem] {
        [
            .text("Space: Clear table", order: 27),
        ]
    }

    // MARK: - Lifecycle

    func new() {
        clearTable()
        cardManager.addCardAtOffsetAtCenter()
    }

    func save() {
        print("Divine: save/render not supported.")
    }

    func toggleHUD() {
        state.toggleHUD()
    }

    func togglePause() {
        state.togglePause()
    }

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
        clearTable()
        cardManager.addCardAtOffsetAtCenter()
    }

    // MARK: - Card/Source Management

    func addCard() {
        cardManager.addCardAtOffsetAtCenter()
    }

    func nextCard() {
        cardManager.nextSource()
    }

    func previousCard() {
        cardManager.previousSource()
    }

    func selectCard(index: Int) {
        cardManager.selectSource(index: index)
    }

    func deleteCurrentCard() {
        cardManager.deleteCurrent()
    }

    func newRandomCard() {
        cardManager.addCardAtOffsetAtCenter()
    }

    func redeal() {
        clearTable()
        cardManager.addCardAtOffsetAtCenter()
    }

    private func clearTable() {
        cardManager.reset()
        resetViewTransform()
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
}
