import SwiftUI
import AppKit

@main
struct HypnogramApp: App {
    @StateObject private var viewModel: HypnogramViewModel
    @StateObject private var renderQueue: RenderQueue

    init() {
        // TODO: adjust this path to wherever you put your config JSON.
        let configURL = URL(fileURLWithPath: "/Users/lorenjohnson/dev/artdev/hypnogram-config.json")

        let config: HypnogramConfig
        do {
            config = try ConfigLoader.load(from: configURL)
            print("Loaded HypnogramConfig from \(configURL.path)")
        } catch {
            // Fallback config so the app still runs if the file is missing/broken.
            print("Failed to load config from \(configURL.path): \(error)")
            config = HypnogramConfig(
                sourceFolders: ["/Users/loren/Movies/hypnogram_sources"],
                clipLengthSeconds: 30,
                maxLayers: 3,
                blendModes: ["multiply", "softlight", "overlay"],
                outputFolder: "/Users/loren/Movies/hypnogram_renders"
            )
        }

        let outputURL = URL(fileURLWithPath: config.outputFolder, isDirectory: true)

        // Use native AVFoundation backend:
        let backend = AVRenderBackend(outputFolder: outputURL)

        // (Optional: keep JSON backend around for debugging)
        // let backend = JSONRecipeBackend(outputFolder: outputURL)

        let queue = RenderQueue(backend: backend)
        let vm = HypnogramViewModel(config: config, renderQueue: queue)

        _renderQueue = StateObject(wrappedValue: queue)
        _viewModel = StateObject(wrappedValue: vm)

        // When all queued renders are finished (after Esc), terminate the app.
        queue.onAllJobsFinished = {
            NSApp.terminate(nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, renderQueue: renderQueue)
                .onAppear {
                    // Start fullscreen to feel like an instrument.
                    NSApp.windows.first?.toggleFullScreen(nil)
                }
        }
        //  The hidden buttons in ContentView are enough to drive everything.
        .commands {
            CommandMenu("Hypnogram Controls") {
                Button("Next Candidate") {
                    viewModel.nextCandidate()
                }
                .keyboardShortcut("n", modifiers: [])

                Button("Accept Candidate") {
                    viewModel.acceptCandidate()
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("Cycle Blend Mode") {
                    viewModel.cycleBlendMode()
                }
                .keyboardShortcut("m", modifiers: [])

                Button("Render Hypnogram") {
                    viewModel.renderCurrentHypnogram()
                }
                .keyboardShortcut("r", modifiers: [])

                Divider()

                Button("Back") {
                    viewModel.handleEscape()
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
        }
    }
}
