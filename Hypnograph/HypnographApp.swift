import SwiftUI
import AppKit

extension NSWindow {
    func makeHypnographBorderless(on screen: NSScreen, contentSize: CGSize) {
        let visible = screen.visibleFrame

        // Maintain the content aspect ratio, scaling down uniformly
        // if either dimension would exceed the visible frame.
        let scaleX = visible.width  / contentSize.width
        let scaleY = visible.height / contentSize.height
        let scale  = min(scaleX, scaleY, 1.0)

        let width  = contentSize.width  * scale
        let height = contentSize.height * scale

        let originX = visible.midX - width  / 2.0
        let originY = visible.midY - height / 2.0
        let frame = NSRect(x: originX, y: originY, width: width, height: height)

        // Remove title bar & traffic lights
        styleMask.remove(.titled)
        styleMask.remove(.closable)
        styleMask.remove(.miniaturizable)
        styleMask.remove(.resizable)   // keep if you want manual resize

        // Ensure we don't participate in macOS fullscreen Spaces
        collectionBehavior = [.fullScreenNone, .canJoinAllSpaces]

        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        isOpaque = true
        backgroundColor = .black
        level = .normal

        setFrame(frame, display: true, animate: false)
        isMovable = false
    }
}

@main
struct HypnographApp: App {
    @StateObject private var viewModel: ViewModel
    @StateObject private var renderQueue: RenderQueue

    init() {
        // Ensure user settings file exists (copy from bundle if missing)
        Environment.ensureDefaultSettingsFileExists()

        // Always load from Application Support
        let settingsURL = Environment.defaultSettingsURL

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
                outputFolder: "~/Movies/Hypnograph/Renders",
                outputHeight: 1080,
                outputSeconds: 30,
                outputWidth: 1920,
                sourceFolders: [ "~/Movies/Hypnograph/Sources" ]
            )
        }

        let outputPath = settings.outputFolder
        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)

        let backend = AVFoundationRenderer(
            outputFolder: outputURL,
            outputWidth: settings.outputWidth,
            outputHeight: settings.outputHeight
        )

        let queue = RenderQueue(renderer: backend)
        let vm    = ViewModel(settings: settings, renderQueue: queue)

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

                        window.makeHypnographBorderless(
                            on: targetScreen,
                            contentSize: viewModel.outputSize
                        )
                    }
                }
        }
        .commands {

            // Remove “New Window” and the default “New” options
            CommandGroup(replacing: .newItem) { }

            // Add custom "New Hypnogram"
            CommandGroup(after: .newItem) {
                Button("New (random)") {
                    viewModel.newAutoPrimeSet()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            // Add custom Save behavior
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    viewModel.renderCurrentHypnogram()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }


            // --- REMOVE VIEW MENU ---
//            CommandGroup(replacing: .view) { }

            CommandMenu("Current") {
                Button("Next Candidate") {
                    viewModel.nextCandidate()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Accept Candidate") {
                    viewModel.acceptCandidate()
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("Cycle Blend Mode") {
                    viewModel.cycleBlendMode()
                }
                .keyboardShortcut("m", modifiers: [])

                Divider()

                Button("> Next Layer") {
                    viewModel.nextLayer()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Button("< Previous Layer") {
                    viewModel.prevLayer()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button("Select Layer 1") {
                    viewModel.selectLayer(index: 0)
                }
                .keyboardShortcut("1", modifiers: [])

                Button("Select Layer 2") {
                    viewModel.selectLayer(index: 1)
                }
                .keyboardShortcut("2", modifiers: [])

                Button("Select Layer 3") {
                    viewModel.selectLayer(index: 2)
                }
                .keyboardShortcut("3", modifiers: [])

                Button("Select Layer 4") {
                    viewModel.selectLayer(index: 3)
                }
                .keyboardShortcut("4", modifiers: [])

                Button("Select Layer 5") {
                    viewModel.selectLayer(index: 4)
                }
                .keyboardShortcut("5", modifiers: [])

                Divider()

                Button("Delete current layer") {
                    viewModel.handleEscape()
                }
                .keyboardShortcut(.delete, modifiers: [])


                Divider()

                Button("Toggle HUD") {
                    viewModel.toggleHUD()
                }
                .keyboardShortcut("h", modifiers: [])

                Button("Restart Session, Reloading Settings from File") {
                    viewModel.newSessionReloadingSettings()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Install hypnograph command") {
                    Environment.installCLI()
                }

                Button("Show Settings Folder") {
                    Environment.showSettingsFolderInFinder()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
