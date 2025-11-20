import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var state: HypnogramState
    @ObservedObject var renderQueue: RenderQueue
    var mode: HypnographMode

    // MARK: - Global HUD Items

    private func globalHUDItems() -> [HUDItem] {
        var items: [HUDItem] = []

        // Header
        items.append(.text("Hypnograph", order: 10, font: .headline))
        items.append(.padding(8, order: 11))

        // Queue status
        if renderQueue.activeJobs > 0 {
            items.append(.text("Queue: \(renderQueue.activeJobs)", order: 20, font: .subheadline))
        } else {
            items.append(.text("Queue: 0", order: 20, font: .caption))
        }
        items.append(.padding(8, order: 21))

        items.append(.text("Source \(state.currentLayerIndex + 1) of \(state.maxLayers)", order: 25))
        // Mode-specific items will be inserted here (e.g., order 25, 26, etc.)
        items.append(.padding(16, order: 29))

        // Global keyboard shortcuts
        items.append(.text("N = Next Candidate this layer", order: 30))
        items.append(.text("Return = Accept Candidate", order: 31))
        items.append(.text("Delete = Delete current layer", order: 32))
        items.append(.text("1-5 Switch to layer", order: 33))
        items.append(.padding(16, order: 40))
        items.append(.text("Space = New random Hypnogram", order: 41))
        items.append(.text("Cmd-S = Save Hypnogram", order: 41))
        items.append(.text("Cmd-R = Reload Settings and Restart", order: 42))
        items.append(.text("Shift-Cmd-S = Show Settings Folder", order: 43))

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
                    ForEach(Array(allHUDItems().enumerated()), id: \.offset) { _, item in
                        item.render()
                    }
                }
                .foregroundColor(.white)
                .padding()
            }
        }
        // extra safety: whole scene black
        .background(Color.black)
    }
}
