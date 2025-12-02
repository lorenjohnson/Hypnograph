//
//  HUDView.swift
//  Hypnograph
//
//  HUD overlay system - styled box with dynamic content from modules.
//

import SwiftUI

// MARK: - HUDItem

/// Represents a single item in the HUD overlay.
/// Items are ordered by their `order` value, allowing modes to inject
/// items between global items (e.g., global items at 10, 20, 30; mode items at 15, 25).
struct HUDItem {
    let order: Int
    let content: Content

    enum Content {
        /// A text line with optional font style
        case text(String, font: Font = .caption)

        /// A spacer/padding of specified height
        case padding(CGFloat)

        /// A custom SwiftUI view
        case custom(AnyView)
    }

    // Convenience initializers
    static func text(_ text: String, order: Int, font: Font = .caption) -> HUDItem {
        HUDItem(order: order, content: .text(text, font: font))
    }

    static func padding(_ height: CGFloat, order: Int) -> HUDItem {
        HUDItem(order: order, content: .padding(height))
    }

    static func custom(_ view: AnyView, order: Int) -> HUDItem {
        HUDItem(order: order, content: .custom(view))
    }

    @ViewBuilder
    func render() -> some View {
        switch content {
        case .text(let string, let font):
            Text(string)
                .font(font)
                .foregroundColor(.white)
        case .padding(let height):
            Spacer()
                .frame(height: height)
        case .custom(let view):
            view
        }
    }
}

// MARK: - HUDView

/// A styled HUD overlay.
/// Aggregates global and module-specific HUD items into a semi-transparent box.
struct HUDView: View {
    @ObservedObject var state: HypnographState
    var renderQueue: RenderQueue
    @ObservedObject var dream: Dream
    @ObservedObject var divine: Divine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(allItems().enumerated()), id: \.offset) { index, item in
                item.render()
                    .id(index)
            }
        }
        .foregroundColor(.white)
        .padding(12)
        .background(
            Color.black.opacity(0.6)
                .cornerRadius(10)
        )
    }

    // MARK: - Item Composition

    private func allItems() -> [HUDItem] {
        let global = globalItems()
        let moduleSpecific: [HUDItem]
        switch state.currentModuleType {
        case .dream:
            moduleSpecific = dream.hudItems()
        case .divine:
            moduleSpecific = divine.hudItems()
        }
        return (global + moduleSpecific).sorted { $0.order < $1.order }
    }

    private func globalItems() -> [HUDItem] {
        var items: [HUDItem] = []

        // Header
        items.append(.text("Hypnograph", order: 10, font: .headline))
        let moduleLabel: String
        switch state.currentModuleType {
        case .dream:
            moduleLabel = "Dream"
        case .divine:
            moduleLabel = "Divine"
        }
        items.append(.text(moduleLabel, order: 11, font: .subheadline))
        items.append(.padding(8, order: 15))

        // Queue status
        if renderQueue.activeJobs > 0 {
            items.append(.text("Queue: \(renderQueue.activeJobs)", order: 20, font: .subheadline))
        } else {
            items.append(.text("Queue: 0", order: 20, font: .caption))
        }
        items.append(.padding(8, order: 21))

        // Global status
        items.append(.text("Global Effect (E): \(state.renderHooks.globalEffectName)", order: 22))

        // Divider before source-specific items
        items.append(.padding(16, order: 24))

        // Source-specific items will be inserted here (order 25-29)

        // Divider after source-specific items
        items.append(.padding(16, order: 39))

        items.append(.text("Current Source", order: 40, font: .subheadline))
        // Global keyboard shortcuts
        items.append(.text("R = Rotate 90°", order: 44))
        items.append(.text("N = New random clip", order: 45))
        items.append(.text("Delete = Delete Source", order: 47))

        items.append(.padding(16, order: 49))

        items.append(.text("1-9 = Jump to Source 1-9", order: 50))
        items.append(.text("Space = New random Hypnogram", order: 51))
        items.append(.text("Cmd-S = Save Hypnogram", order: 52))
        items.append(.text("Cmd-R = Reload Settings and Restart", order: 53))
        items.append(.text("Shift-Cmd-S = Show Settings Folder", order: 54))

        return items
    }
}

