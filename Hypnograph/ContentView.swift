import SwiftUI
import AVFoundation
import Combine

struct ContentView: View {
    @ObservedObject var state: HypnogramState
    @ObservedObject var renderQueue: RenderQueue
    var mode: HypnographMode

    // MARK: - Global HUD Items

    private func globalHUDItems() -> [HUDItem] {
        var items: [HUDItem] = []

        // Header
        items.append(.text("Hypnograph", order: 10, font: .headline))
        let modeLabel: String
        switch state.currentModeType {
        case .montage:
            modeLabel = "Montage Mode"
        case .sequence:
            modeLabel = "Sequence Mode"
        case .divine:
            modeLabel = "Divine Mode"
        }
        items.append(.text(modeLabel, order: 11, font: .subheadline))
        items.append(.padding(8, order: 12))

        // Queue status
        if renderQueue.activeJobs > 0 {
            items.append(.text("Queue: \(renderQueue.activeJobs)", order: 20, font: .subheadline))
        } else {
            items.append(.text("Queue: 0", order: 20, font: .caption))
        }
        items.append(.padding(8, order: 21))

        // Global status
        items.append(.text("Global Effect (E): \(mode.globalEffectName)", order: 22))

        // Divider before source-specific items
        items.append(.padding(16, order: 24))

        // Source-specific items will be inserted here (order 25-29)

        // Divider after source-specific items
        items.append(.padding(16, order: 39))

        items.append(.text("Current Source", order: 40, font: .subheadline))
        // Global keyboard shortcuts
        items.append(.text("N = New random clip", order: 42))
        items.append(.text("Delete = Delete Source", order: 44))

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
        let modeSpecific = mode.hudItems(state: state, renderQueue: renderQueue)
        return (global + modeSpecific).sorted { $0.order < $1.order }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Solid black backing for the entire window
            Color.black
                .ignoresSafeArea()

            // Mode-driven display: ContentView doesn't care *what* this is.
            mode.makeDisplayView(state: state, renderQueue: renderQueue)
                .ignoresSafeArea()

            // HUD
            if state.isHUDVisible {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(allHUDItems().enumerated()), id: \.offset) { index, item in
                        item.render()
                            .id(index) // Use the enumeration index as the unique ID
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
            if let text = mode.soloIndicatorText {
                Text(text)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.red)
                    .padding()
            }
        }
        // extra safety: whole scene black
        .background(Color.black)
    }
}
