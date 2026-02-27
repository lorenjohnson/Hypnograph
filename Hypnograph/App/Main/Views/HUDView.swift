//
//  HUDView.swift
//  Hypnograph
//
//  HUD overlay system - styled box with dynamic content from modules.
//

import SwiftUI
import HypnoCore

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
/// Includes source file list at the bottom.
struct HUDView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var dream: Main
    @ObservedObject private var tooltipManager = TooltipManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Module-specific HUD items
            ForEach(Array(hudItems().enumerated()), id: \.offset) { index, item in
                item.render()
                    .id(index)
            }

            // Source file list section
            Spacer().frame(height: 12)

            Text("Layers (\(formattedDuration))")
                    .font(.subheadline)
                    .foregroundColor(.white)

                if dream.activePlayer.layers.isEmpty {
                    Text("No layers")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    ForEach(Array(dream.activePlayer.layers.enumerated()), id: \.offset) { index, layer in
                        HStack(spacing: 4) {
                            Text("\(index + 1):")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(index == dream.activePlayer.currentSourceIndex ? .cyan : .white.opacity(0.7))
                            Text(shortenedPath(layer))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(index == dream.activePlayer.currentSourceIndex ? .cyan : .white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                // Tooltip display section
                if let tooltip = tooltipManager.currentTooltip {
                    Spacer().frame(height: 12)

                    Divider()
                        .background(Color.white.opacity(0.3))

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundColor(.cyan)
                        Text(tooltip)
                            .font(.caption)
                            .foregroundColor(.cyan)
                            .lineLimit(2)
                    }
                    .padding(.top, 4)
                }
        }
        .foregroundColor(.white)
        .padding(12)
        .background(
            Color.black.opacity(0.6)
                .cornerRadius(10)
        )
        .fixedSize()
    }

    private func hudItems() -> [HUDItem] {
        return dream.hudItems().sorted { $0.order < $1.order }
    }

    /// Shorten path by replacing home directory with ~/
    private func shortenedPath(_ source: HypnogramLayer) -> String {
        switch source.mediaClip.file.source {
        case .url(let url):
            let path = url.path
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            if path.hasPrefix(homeDir) {
                return "~" + path.dropFirst(homeDir.count)
            }
            return path
        case .external(let identifier):
            return "external:\(identifier)"
        }
    }

    private var formattedDuration: String {
        let totalSeconds = dream.activePlayer.targetDuration.seconds
        if totalSeconds < 60 {
            return String(format: "%.1fs", totalSeconds)
        } else {
            let minutes = Int(totalSeconds) / 60
            let seconds = Int(totalSeconds) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
