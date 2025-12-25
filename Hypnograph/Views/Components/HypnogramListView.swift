//
//  HypnogramListView.swift
//  Hypnograph
//
//  Panel showing favorited hypnograms, clickable to load.
//

import SwiftUI

/// Tab selection for the list
enum HypnogramListTab: String, CaseIterable {
    case favorites = "Favorites"
    case recent = "Recent"
}

/// Panel displaying saved hypnograms
struct HypnogramListView: View {
    @ObservedObject var store: HypnogramStore
    @State private var selectedTab: HypnogramListTab = .favorites
    @State private var panelSize: CGSize = CGSize(width: 420, height: 400)

    /// Called when user wants to load a hypnogram
    var onLoad: (HypnogramEntry) -> Void

    private let minWidth: CGFloat = 320
    private let minHeight: CGFloat = 250
    private let maxWidth: CGFloat = 600
    private let maxHeight: CGFloat = 800

    var body: some View {
        VStack(spacing: 0) {
            // Header with drag handle hint
            HStack {
                Spacer()
                Text("Hypnograms")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(HypnogramListTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)

            // List content
            ScrollView {
                LazyVStack(spacing: 6) {
                    let entries = selectedTab == .favorites ? store.favorites : store.recent

                    if entries.isEmpty {
                        Text(selectedTab == .favorites ? "No favorites yet" : "No saved hypnograms")
                            .foregroundColor(.white.opacity(0.5))
                            .font(.system(.body, design: .monospaced))
                            .padding(.vertical, 40)
                    } else {
                        ForEach(entries) { entry in
                            HypnogramRowView(entry: entry, onLoad: onLoad, onToggleFavorite: {
                                store.toggleFavorite(entry)
                            })
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }

            Spacer(minLength: 0)

            // Resize handle
            HStack {
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                    .rotationEffect(.degrees(45))
                    .padding(6)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newWidth = panelSize.width + value.translation.width
                                let newHeight = panelSize.height + value.translation.height
                                panelSize.width = min(max(newWidth, minWidth), maxWidth)
                                panelSize.height = min(max(newHeight, minHeight), maxHeight)
                            }
                    )
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
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

