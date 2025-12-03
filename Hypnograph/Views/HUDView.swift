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
/// Renders module-specific HUD items into a semi-transparent box.
struct HUDView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var dream: Dream
    @ObservedObject var divine: Divine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(hudItems().enumerated()), id: \.offset) { index, item in
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

    private func hudItems() -> [HUDItem] {
        switch state.currentModuleType {
        case .dream:
            return dream.hudItems().sorted { $0.order < $1.order }
        case .divine:
            return divine.hudItems().sorted { $0.order < $1.order }
        }
    }
}

// MARK: - InfoHUD

/// Info HUD showing source list and composition details
struct InfoHUD: View {
    @ObservedObject var state: HypnographState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sources")
                .font(.headline)
                .foregroundColor(.white)

            if state.sources.isEmpty {
                Text("No sources")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            } else {
                ForEach(Array(state.sources.enumerated()), id: \.offset) { index, source in
                    Text("\(index + 1): \(sourcePath(source))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer().frame(height: 8)

            Text("Total: \(formattedDuration)")
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(12)
        .background(
            Color.black.opacity(0.6)
                .cornerRadius(10)
        )
    }

    private func sourcePath(_ source: HypnogramSource) -> String {
        switch source.clip.file.source {
        case .url(let url):
            return url.path
        case .photos(let identifier):
            return "photos:\(identifier)"
        }
    }

    private var formattedDuration: String {
        let totalSeconds = state.recipe.targetDuration.seconds
        if totalSeconds < 60 {
            return String(format: "%.1fs", totalSeconds)
        } else {
            let minutes = Int(totalSeconds) / 60
            let seconds = Int(totalSeconds) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

