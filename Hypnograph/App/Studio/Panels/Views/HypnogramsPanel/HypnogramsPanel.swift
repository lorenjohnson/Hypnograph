//
//  HypnogramsPanel.swift
//  Hypnograph
//
//  Panel showing favorited hypnograms, clickable to load.
//

import SwiftUI
/// Tab selection for the list
enum HypnogramsPanelTab: String, CaseIterable {
    case recent = "Recently Saved"
    case favorites = "Favorites"
}

/// Panel displaying saved hypnograms
struct HypnogramsPanel: View {
    let recentEntries: [HypnogramEntry]
    let favoriteEntries: [HypnogramEntry]
    @AppStorage("studio.hypnogramsPanel.selectedTab")
    private var selectedTabRawValue: String = HypnogramsPanelTab.recent.rawValue

    /// Called when user wants to load a hypnogram
    var onLoad: (HypnogramEntry) -> Void
    var onToggleFavorite: (HypnogramEntry) -> Void

    private var selectedTab: Binding<HypnogramsPanelTab> {
        Binding(
            get: { HypnogramsPanelTab(rawValue: selectedTabRawValue) ?? .recent },
            set: { selectedTabRawValue = $0.rawValue }
        )
    }

    private var currentSelectedTab: HypnogramsPanelTab {
        HypnogramsPanelTab(rawValue: selectedTabRawValue) ?? .recent
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: selectedTab) {
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
                    switch currentSelectedTab {
                    case .recent, .favorites:
                        let entries = currentSelectedTab == .favorites ? favoriteEntries : recentEntries

                        if entries.isEmpty {
                            emptyStateText(currentSelectedTab == .favorites ? "No favorites yet" : "No saved hypnograms")
                        } else {
                            ForEach(entries) { entry in
                                HypnogramRowView(
                                    entry: entry,
                                    onLoad: onLoad,
                                    onToggleFavorite: {
                                        onToggleFavorite(entry)
                                    }
                                )
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
            ThumbnailView(image: entry.thumbnailImage)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipped()

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

            Button(action: onToggleFavorite) {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
                    .foregroundColor(entry.isFavorite ? .yellow : .white.opacity(0.5))
                    .font(.system(size: 18))
            }
            .buttonStyle(.borderless)
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
    var fill: Bool = false

    var body: some View {
        ZStack {
            if let image = image {
                Color.white.opacity(0.05)
                Image(nsImage: image)
                    .resizable()
                    .modifier(ThumbnailScalingModifier(fill: fill))
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

private struct ThumbnailScalingModifier: ViewModifier {
    let fill: Bool

    func body(content: Content) -> some View {
        if fill {
            content.scaledToFill()
        } else {
            content.scaledToFit()
        }
    }
}
