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
    @StateObject private var session: HypnogramState
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

        let backend = MontageRenderer(
            outputFolder: outputURL,
            outputWidth: settings.outputWidth,
            outputHeight: settings.outputHeight
        )

        let queue   = RenderQueue(renderer: backend)
        let session = HypnogramState(settings: settings)

        _renderQueue = StateObject(wrappedValue: queue)
        _session     = StateObject(wrappedValue: session)

        queue.onAllJobsFinished = { NSApp.terminate(nil) }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(session: session, renderQueue: renderQueue)
                .onAppear {
                    DispatchQueue.main.async {
                        guard let window = NSApp.windows.first else { return }

                        let screens = NSScreen.screens
                        // Prefer external monitor if present
                        let targetScreen = (screens.count > 1 ? screens[1] : screens[0])

                        window.makeHypnographBorderless(
                            on: targetScreen,
                            contentSize: session.outputSize
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
                    session.newAutoPrimeSet()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            // Add custom Save behavior
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    guard let recipe = session.layersForRender() else {
                        print("renderCurrentHypnogram(): no renderable hypnogram (no selected clips).")
                        return
                    }

                    print("renderCurrentHypnogram(): enqueuing recipe with \(recipe.layers.count) layer(s).")
                    renderQueue.enqueue(recipe: recipe)

                    session.resetForNextHypnogram()

                    if session.settings.autoPrime {
                        session.newAutoPrimeSet()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command])
            }

            CommandMenu("Current") {
                Button("Next Candidate") {
                    session.nextCandidate()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Accept Candidate") {
                    session.acceptCandidate()
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("Cycle Blend Mode") {
                    session.cycleBlendMode()
                }
                .keyboardShortcut("m", modifiers: [])

                Divider()

                Button("> Next Layer") {
                    session.nextLayer()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Button("< Previous Layer") {
                    session.prevLayer()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button("Select Layer 1") {
                    session.selectLayer(index: 0)
                }
                .keyboardShortcut("1", modifiers: [])

                Button("Select Layer 2") {
                    session.selectLayer(index: 1)
                }
                .keyboardShortcut("2", modifiers: [])

                Button("Select Layer 3") {
                    session.selectLayer(index: 2)
                }
                .keyboardShortcut("3", modifiers: [])

                Button("Select Layer 4") {
                    session.selectLayer(index: 3)
                }
                .keyboardShortcut("4", modifiers: [])

                Button("Select Layer 5") {
                    session.selectLayer(index: 4)
                }
                .keyboardShortcut("5", modifiers: [])

                Divider()

                Button("Delete current layer") {
                    session.handleEscape()
                }
                .keyboardShortcut(.delete, modifiers: [])

                Divider()

                Button("Toggle HUD") {
                    session.toggleHUD()
                }
                .keyboardShortcut("h", modifiers: [])

                Button("Restart Session, Reloading Settings from File") {
                    session.reloadSettings(from: Environment.defaultSettingsURL)
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
