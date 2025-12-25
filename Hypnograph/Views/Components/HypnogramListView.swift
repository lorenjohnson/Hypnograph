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

    /// Called when user wants to load a hypnogram
    var onLoad: (HypnogramEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(HypnogramListTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // List content
            ScrollView {
                LazyVStack(spacing: 4) {
                    let entries = selectedTab == .favorites ? store.favorites : store.recent

                    if entries.isEmpty {
                        Text(selectedTab == .favorites ? "No favorites yet" : "No saved hypnograms")
                            .foregroundColor(.white.opacity(0.5))
                            .font(.system(.body, design: .monospaced))
                            .padding(.vertical, 20)
                    } else {
                        ForEach(entries) { entry in
                            HypnogramRowView(entry: entry, onLoad: onLoad, onToggleFavorite: {
                                store.toggleFavorite(entry)
                            })
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 280, height: 200)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Row view for a single hypnogram entry
struct HypnogramRowView: View {
    let entry: HypnogramEntry
    let onLoad: (HypnogramEntry) -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Thumbnail placeholder (future: actual thumbnail)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "photo.stack")
                        .foregroundColor(.white.opacity(0.3))
                        .font(.system(size: 16))
                )

            // Name and date
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(entry.createdAt, style: .date)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            // Favorite button
            Button(action: onToggleFavorite) {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
                    .foregroundColor(entry.isFavorite ? .yellow : .white.opacity(0.5))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            onLoad(entry)
        }
    }
}

