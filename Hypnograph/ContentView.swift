import SwiftUI
import AVFoundation
import Combine

struct ContentView: View {
    @ObservedObject var state: HypnographState
    var renderQueue: RenderQueue  // Not @ObservedObject - we don't want to trigger view updates
    @ObservedObject var dream: Dream
    @ObservedObject var divine: Divine

    // MARK: - Global HUD Items

    private func globalHUDItems() -> [HUDItem] {
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

    private func allHUDItems() -> [HUDItem] {
        let global = globalHUDItems()
        let moduleSpecific: [HUDItem]
        switch state.currentModuleType {
        case .dream:
            moduleSpecific = dream.hudItems(state: state, renderQueue: renderQueue)
        case .divine:
            moduleSpecific = divine.hudItems()
        }
        return (global + moduleSpecific).sorted { $0.order < $1.order }
    }

    private var soloIndicatorText: String? {
        // Only Dream shows solo indicator
        if state.currentModuleType == .dream, !state.sources.isEmpty {
            return "\(state.currentSourceIndex + 1)/\(state.sources.count)"
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Solid black backing for the entire window
            Color.black
                .ignoresSafeArea()

            // Module-specific display
            switch state.currentModuleType {
            case .dream:
                dream.makeDisplayView(state: state, renderQueue: renderQueue)
                    .ignoresSafeArea()
            case .divine:
                divine.makeDisplayView()
                    .ignoresSafeArea()
            }

            // HUD
            if state.isHUDVisible {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(allHUDItems().enumerated()), id: \.offset) { index, item in
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
                .padding(.top, 12)
                .padding(.leading, 12)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let text = soloIndicatorText {
                Text(text)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .background(Color.black)
    }
}
