//
//  HypnogramsPanel.swift
//  Hypnograph
//
//  Panel showing favorited hypnograms, clickable to load.
//

import SwiftUI
import HypnoCore

/// Tab selection for the list
enum HypnogramsPanelTab: String, CaseIterable {
    case history = "History"
    case recent = "Recently Saved"
    case favorites = "Favorites"
}

struct HistoryCompositionEntry: Identifiable {
    let index: Int
    let composition: Composition
    let isCurrent: Bool

    var id: Int { index }

    var thumbnailImage: NSImage? {
        CompositionPreviewImageCodec.decodeImage(from: composition.thumbnail ?? composition.snapshot)
    }
}

/// Panel displaying saved hypnograms
struct HypnogramsPanel: View {
    @ObservedObject var store: HypnogramStore
    let historyEntries: [HistoryCompositionEntry]
    @State private var selectedTab: HypnogramsPanelTab = .recent

    /// Called when user wants to load a hypnogram
    var onLoad: (HypnogramEntry) -> Void
    var onJumpToHistory: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(HypnogramsPanelTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue)
                        .foregroundColor(.white)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .colorScheme(.dark)
            .padding(12)

            ScrollView {
                LazyVStack(spacing: 6) {
                    switch selectedTab {
                    case .history:
                        if historyEntries.isEmpty {
                            emptyStateText("No history yet")
                        } else {
                            ForEach(historyEntries) { entry in
                                HistoryCompositionRowView(
                                    entry: entry,
                                    onJump: {
                                        onJumpToHistory(entry.index)
                                    }
                                )
                            }
                        }
                    case .recent, .favorites:
                        let entries = selectedTab == .favorites ? store.favorites : store.recent

                        if entries.isEmpty {
                            emptyStateText(selectedTab == .favorites ? "No favorites yet" : "No saved hypnograms")
                        } else {
                            ForEach(entries) { entry in
                                HypnogramRowView(entry: entry, onLoad: onLoad, onToggleFavorite: {
                                    store.toggleFavorite(entry)
                                })
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }

    @ViewBuilder
    private func emptyStateText(_ text: String) -> some View {
        Text(text)
            .foregroundColor(.white.opacity(0.5))
            .font(.system(.body, design: .monospaced))
            .padding(.vertical, 40)
    }
}

/// Row view for a single hypnogram entry
struct HypnogramRowView: View {
    let entry: HypnogramEntry
    let onLoad: (HypnogramEntry) -> Void
    let onToggleFavorite: () -> Void

    private let thumbnailSize: CGFloat = 60

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Thumbnail - fixed size, clipped to bounds
            ThumbnailView(image: entry.thumbnailImage)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipped()

            // Name and date
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(entry.createdAt, style: .date)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Favorite button
            Button(action: onToggleFavorite) {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
                    .foregroundColor(entry.isFavorite ? .yellow : .white.opacity(0.5))
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .frame(width: 30)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            onLoad(entry)
        }
    }
}

/// Thumbnail view that displays an NSImage or placeholder
struct ThumbnailView: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // Placeholder
                Color.white.opacity(0.1)
                Image(systemName: "photo.stack")
                    .foregroundColor(.white.opacity(0.3))
                    .font(.system(size: 20))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct HistoryCompositionRowView: View {
    let entry: HistoryCompositionEntry
    let onJump: () -> Void

    private var layerCountText: String {
        let count = entry.composition.layers.count
        return "\(count) layer\(count == 1 ? "" : "s")"
    }

    private var durationText: String {
        let seconds = max(0.1, entry.composition.targetDuration.seconds)
        let rounded = (seconds * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return "\(Int(rounded.rounded()))s"
        }
        return String(format: "%.1fs", rounded)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ThumbnailView(image: entry.thumbnailImage)
                .frame(width: 60, height: 60)
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Composition \(entry.index + 1)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)

                    if entry.isCurrent {
                        Text("CURRENT")
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                }

                Text("\(layerCountText) • \(durationText)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))

                Text(entry.composition.createdAt, style: .date)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.turn.down.right")
                .foregroundColor(.white.opacity(0.5))
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(entry.isCurrent ? Color.blue.opacity(0.16) : Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            onJump()
        }
    }
}
