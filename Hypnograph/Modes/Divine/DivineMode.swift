//
//  DivineMode.swift
//  Hypnograph
//
//  Tarot-style stills mode with drag-and-drop cards from a bottom-right deck.
//

import SwiftUI
import AVFoundation
import CoreMedia
import CoreGraphics

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

/// Tarot-style stills mode with drag-and-drop cards.
final class DivineMode: HypnographMode {
    let state: HypnographState
    let renderQueue: RenderQueue

    /// Placeholder renderer for protocol completeness (not actually used yet).
    private let renderer = DivineNoopRenderer()

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

    // MARK: - HypnographMode – display wiring

    func makeDisplayView(
        state: HypnographState,
        renderQueue: RenderQueue
    ) -> AnyView {
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

    func hudItems(state: HypnographState, renderQueue: RenderQueue) -> [HUDItem] {
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

    func sourceCommands() -> [ModeCommand] {
        []
    }

    // MARK: - HypnographMode – lifecycle

    func new() {
        clearTable()
        cardManager.addCardAtOffsetAtCenter()
    }

    func save() {
        print("DivineMode: save / render not supported.")
    }

    // MARK: - HypnographMode – source navigation

    func addSource() {
        cardManager.addCardAtOffsetAtCenter()
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

    // MARK: - HypnographMode – clip / selection

    /// In Divine, "New Random Clip" = draw another card onto the table.
    func newRandomClip() {
        cardManager.addCardAtOffsetAtCenter()
    }

    func deleteCurrentSource() {
        cardManager.deleteCurrent()
    }

    // MARK: - HypnographMode – mode-specific tweaks

    func reloadSettings() {
        state.reloadSettings(from: Environment.defaultSettingsURL)
        clearTable()
        cardManager.addCardAtOffsetAtCenter()
    }

    // MARK: - HypnographMode – effects

    /// Divine only clears the current source's effect + global.
    func clearAllEffects() {
        state.renderHooks.setGlobalEffect(nil)
        state.renderHooks.setSourceEffect(nil, for: cardManager.currentIndex)
    }

    var globalEffectName: String {
        state.renderHooks.globalEffectName
    }

    var sourceEffectName: String {
        state.renderHooks.sourceEffectName(for: cardManager.currentIndex)
    }

    // MARK: - Divine-specific helpers

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
