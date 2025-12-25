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
        var items: [HUDItem] = []

        // Header
        items.append(.text("Hypnograph", order: 10, font: .headline))
        items.append(.text("Divine", order: 11, font: .subheadline))
        items.append(.padding(8, order: 15))

        // Card count
        items.append(.text("Cards: \(cardManager.cards.count)", order: 20))
        items.append(.padding(16, order: 24))

        // Keyboard hints
        items.append(.text("Shortcuts", order: 40, font: .subheadline))
        items.append(.text("N = Clear table", order: 41))
        items.append(.text(". = Add card | ⇧N = New card", order: 42))
        items.append(.text("←/→ = Navigate | 1-9 = Select card", order: 43))
        items.append(.text("Delete = Remove card", order: 44))
        items.append(.text("Drag cards to arrange", order: 45))

        return items
    }

    // MARK: - Menus

    @ViewBuilder
    func compositionMenu() -> some View {
        Button("Add Card") { [self] in
            addCard()
        }
        .keyboardShortcut(".", modifiers: [])

        Button("> Next Card") { [self] in
            nextCard()
        }
        .keyboardShortcut(.rightArrow, modifiers: [])

        Button("< Previous Card") { [self] in
            previousCard()
        }
        .keyboardShortcut(.leftArrow, modifiers: [])

        ForEach(0..<9, id: \.self) { idx in
            Button("Select Card \(idx + 1)") { [self] in
                selectCard(index: idx)
            }
            .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
        }

        Divider()

        Button("Clear Table") { [self] in
            new()
        }
        .keyboardShortcut("n", modifiers: [.command])

        Divider()

        Button("Zoom In") { [self] in
            zoomInStep()
        }
        .keyboardShortcut("+", modifiers: [.command])

        Button("Zoom Out") { [self] in
            zoomOutStep()
        }
        .keyboardShortcut("-", modifiers: [.command])

        Button("Reset Zoom") { [self] in
            resetViewTransform()
        }
        .keyboardShortcut("0", modifiers: [.command])
    }

    @ViewBuilder
    func sourceMenu() -> some View {
        Button("New Random Card") { [self] in
            newRandomCard()
        }
        .keyboardShortcut("n", modifiers: [.shift])

        Divider()

        Button("Delete Card") { [self] in
            deleteCurrentCard()
        }
        .keyboardShortcut(.delete, modifiers: [])

        Button("Add to Exclude List") { [self] in
            excludeCurrentCardSource()
        }
        .keyboardShortcut("x", modifiers: [.shift])

        Button("Toggle Favorite") { [self] in
            toggleCurrentCardFavorite()
        }
        .keyboardShortcut("f", modifiers: [.shift])
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
        // Divine doesn't currently have HUD support
    }

    func togglePause() {
        // Divine doesn't have video playback - pause is a no-op
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

    func excludeCurrentCardSource() {
        state.noteUserInteraction()
        guard let card = cardManager.selectedCard else { return }
        state.library.exclude(file: card.clip.file)
        // Replace with new random card
        cardManager.replaceCurrentCard()
    }

    func toggleCurrentCardFavorite() {
        state.noteUserInteraction()
        guard let card = cardManager.selectedCard else { return }
        let isFavorited = FavoriteStore.shared.toggle(card.clip.file.source)
        let message = isFavorited ? "Added to favorites" : "Removed from favorites"
        AppNotifications.shared.show(message, flash: true)
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
