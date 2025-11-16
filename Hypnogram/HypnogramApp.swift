import SwiftUI
import AppKit

extension NSWindow {
    func makeHypnogramBorderless(on screen: NSScreen) {
        let frame = screen.visibleFrame

        // Remove title bar & traffic lights
        styleMask.remove(.titled)
        styleMask.remove(.closable)
        styleMask.remove(.miniaturizable)
        styleMask.remove(.resizable)   // optional: keep if you want manual resize

        // Ensure we don't participate in macOS fullscreen Spaces
        collectionBehavior = [.fullScreenNone, .canJoinAllSpaces]

        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        isOpaque = true
        backgroundColor = .black
        level = .normal      // or .statusBar if you want it above everything

        setFrame(frame, display: true, animate: false)
        isMovable = false
    }
}

@main
struct HypnogramApp: App {
    @StateObject private var viewModel: ViewModel
    @StateObject private var renderQueue: RenderQueue

    init() {
        // Ensure user settings file exists (copy from bundle if missing)
        AppSettingsPaths.ensureDefaultConfigFileExists()

        // Always load from Application Support
        let settingsURL = AppSettingsPaths.defaultConfigURL

        let settings: Settings
        do {
            settings = try SettingsLoader.load(from: settingsURL)
            print("Loaded settings from \(settingsURL.path)")
        } catch {
            // Absolutely minimal fallback
            print("⚠️ Failed to load settings, using emergency fallback: \(error)")

            settings = Settings(
                autoPrime: true,
                autoPrimeTimeout: 30,
                blendModes: [
                    "screen",
                    "overlay",
                    "softlight",
                    "multiply",
                    "darken",
                    "lighten",
                    "difference",
                    "exclusion"
                ],
                maxLayers: 3,
                outputFolder: "~/Movies/Hypnogram/Renders",
                outputHeight: 1080,
                outputSeconds: 30,
                outputWidth: 1920,
                sourceFolders: [ "~/Movies/Hypnogram/Sources" ]
            )
        }

        let outputPath = (settings.outputFolder as NSString).expandingTildeInPath
        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)

        let backend = AVRenderBackend(
            outputFolder: outputURL,
            outputWidth: settings.outputWidth,
            outputHeight: settings.outputHeight
        )

        let queue = RenderQueue(backend: backend)
        let vm = ViewModel(settings: settings, renderQueue: queue)

        _renderQueue = StateObject(wrappedValue: queue)
        _viewModel = StateObject(wrappedValue: vm)

        queue.onAllJobsFinished = { NSApp.terminate(nil) }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, renderQueue: renderQueue)
                .onAppear {
                    DispatchQueue.main.async {
                        guard let window = NSApp.windows.first else { return }

                        let screens = NSScreen.screens
                        // Prefer external monitor if present
                        let targetScreen = (screens.count > 1 ? screens[1] : screens[0])

                        window.makeHypnogramBorderless(on: targetScreen)
                    }
                }
        }
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

                Button("Back") {
                    viewModel.handleEscape()
                }
                .keyboardShortcut(.delete, modifiers: [])

                Divider()

                Button("New AutoPrime Set") {
                    viewModel.newAutoPrimeSet()
                }
                .keyboardShortcut(.space, modifiers: [])                

                Button("Randomize Layer 1") {
                    viewModel.randomizeLayer(index: 0)
                }
                .keyboardShortcut("1", modifiers: [])

                Button("Randomize Layer 2") {
                    viewModel.randomizeLayer(index: 1)
                }
                .keyboardShortcut("2", modifiers: [])

                Button("Randomize Layer 3") {
                    viewModel.randomizeLayer(index: 2)
                }
                .keyboardShortcut("3", modifiers: [])

                Button("Randomize Layer 4") {
                    viewModel.randomizeLayer(index: 3)
                }
                .keyboardShortcut("4", modifiers: [])

                Button("Randomize Layer 5") {
                    viewModel.randomizeLayer(index: 4)
                }
                .keyboardShortcut("5", modifiers: [])

                Divider()

                Button("Toggle HUD") {
                    viewModel.toggleHUD()
                }
                .keyboardShortcut("h", modifiers: [])

                Button("Install hypnograph command") {
                    AppSettingsPaths.installHypnographCLI()
                }

                Button("Show Settings Folder") {
                    AppSettingsPaths.showSettingsFolderInFinder()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
