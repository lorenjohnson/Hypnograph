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
    private let settings: Settings
    @StateObject private var state: HypnogramState
    @StateObject private var renderQueue: RenderQueue
    private let mode: HypnographMode

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

        // Shared state
        self.settings = settings
        let state = HypnogramState(settings: settings)

        let montageMode = MontageMode(state: state, settings: settings)

        _state       = StateObject(wrappedValue: state)
        _renderQueue = StateObject(wrappedValue: montageMode.renderQueue)

        self.mode = montageMode

        montageMode.renderQueue.onAllJobsFinished = { NSApp.terminate(nil) }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(
                state: state,
                renderQueue: renderQueue,
                mode: mode
            )
            .onAppear {
                DispatchQueue.main.async {
                    guard let window = NSApp.windows.first else { return }

                    let screens = NSScreen.screens
                    // Prefer external monitor if present
                    let targetScreen = (screens.count > 1 ? screens[1] : screens[0])

                    window.makeHypnographBorderless(
                        on: targetScreen,
                        contentSize: settings.outputSize
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
                    mode.newRandomHypnogram()
                }
                .keyboardShortcut(.space, modifiers: [])
            }
            
            // Add custom Save behavior
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    mode.saveCurrentHypnogram()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
            
            CommandMenu("Current") {
                Button("Cycle Blend Mode") {
                    mode.cycleEffect()
                }
                .keyboardShortcut("m", modifiers: [])
                
                Button("New Clip") {
                    mode.nextCandidate()
                }
                .keyboardShortcut("n", modifiers: [])
                
                Button("Next Layer") {
                    mode.acceptCandidate()
                }
                .keyboardShortcut(.return, modifiers: [])
                
                Divider()
                
                Button("> Next Source") {
                    mode.nextSource()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                
                Button("< Previous Source") {
                    mode.previousSource()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                
                Button("Select Source 1") {
                    mode.selectSource(index: 0)
                }
                .keyboardShortcut("1", modifiers: [])
                
                Button("Select Source 2") {
                    mode.selectSource(index: 1)
                }
                .keyboardShortcut("2", modifiers: [])
                
                Button("Select Source 3") {
                    mode.selectSource(index: 2)
                }
                .keyboardShortcut("3", modifiers: [])
                
                Button("Select Source 4") {
                    mode.selectSource(index: 3)
                }
                .keyboardShortcut("4", modifiers: [])
                
                Button("Select Source 5") {
                    mode.selectSource(index: 4)
                }
                .keyboardShortcut("5", modifiers: [])
                
                Divider()
                
                Button("Delete current source") {
                    mode.deleteCurrentSource()
                }
                .keyboardShortcut(.delete, modifiers: [])
                
                Divider()
                
                Button("Toggle HUD") {
                    mode.toggleHUD()
                }
                .keyboardShortcut("h", modifiers: [])
                
                Button("Restart Session, Reloading Settings from File") {
                    mode.reloadSettings()
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
