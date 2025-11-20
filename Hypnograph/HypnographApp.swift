import SwiftUI
import AppKit

extension NSWindow {
    func makeHypnographBorderless(on screen: NSScreen, contentSize: CGSize) {
        // Use full screen frame (not visibleFrame) so we extend under the menu bar / notch.
        let fullFrame = screen.frame

        // Take the entire frame so black background fills the whole display.
        let frame = fullFrame

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
        // Lift window above the menu bar without entering macOS fullscreen Spaces.
        level = .statusBar

        setFrame(frame, display: true, animate: false)
        isMovable = false
    }
}


// MARK: - App Delegate

final class HypnographAppDelegate: NSObject, NSApplicationDelegate {
    weak var renderQueue: RenderQueue?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let queue = renderQueue else {
            return .terminateNow
        }

        if queue.activeJobs == 0 {
            return .terminateNow
        }

        print("Hypnograph: delaying termination until \(queue.activeJobs) render job(s) complete")

        // When all jobs finish, tell AppKit it's okay to quit.
        queue.onAllJobsFinished = { [weak sender] in
            DispatchQueue.main.async {
                sender?.reply(toApplicationShouldTerminate: true)
            }
        }

        return .terminateLater
    }
}

@main
struct HypnographApp: App {
    @NSApplicationDelegateAdaptor(HypnographAppDelegate.self)
    private var appDelegate

    private let settings: Settings
    @StateObject private var state: HypnogramState
    @StateObject private var montageMode: MontageMode
    @StateObject private var sequenceMode: SequenceMode

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

        GlobalRenderHooks.manager = state.renderHooks

        _state = StateObject(wrappedValue: state)
        _montageMode = StateObject(wrappedValue: MontageMode(state: state))
        _sequenceMode = StateObject(wrappedValue: SequenceMode(state: state))
    }

    var currentMode: HypnographMode {
        switch state.currentModeType {
        case .montage:
            return montageMode
        case .sequence:
            return sequenceMode
        }
    }

    func cycleMode() {
        switch state.currentModeType {
        case .montage:
            state.currentModeType = .sequence
            appDelegate.renderQueue = sequenceMode.renderQueue
        case .sequence:
            state.currentModeType = .montage
            appDelegate.renderQueue = montageMode.renderQueue
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                state: state,
                renderQueue: currentMode.renderQueue,
                mode: currentMode
            )
            .onAppear {
                DispatchQueue.main.async {
                    guard let window = NSApp.windows.first else { return }

                    let screens = NSScreen.screens
                    // Prefer external monitor if present
                    let targetScreen = (screens.count > 1 ? screens[1] : screens[0])

                    window.makeHypnographBorderless(
                        on: targetScreen,
                        contentSize: state.settings.outputSize
                    )
                }

                // Set initial render queue
                appDelegate.renderQueue = montageMode.renderQueue
            }
        }
        .commands {
            AppCommands(
                state: state,
                montageMode: montageMode,
                sequenceMode: sequenceMode,
                appDelegate: appDelegate,
                cycleMode: cycleMode
            )
        }
    }
}

// Singleton to hold the modes for command access
class ModeHolder {
    static let shared = ModeHolder()
    var montageMode: MontageMode?
    var sequenceMode: SequenceMode?
    var state: HypnogramState?
    var appDelegate: HypnographAppDelegate?

    private init() {}

    var currentMode: HypnographMode? {
        guard let state = state else { return nil }
        switch state.currentModeType {
        case .montage:
            return montageMode
        case .sequence:
            return sequenceMode
        }
    }

    func cycleMode() {
        guard let state = state else { return }
        switch state.currentModeType {
        case .montage:
            state.currentModeType = .sequence
            appDelegate?.renderQueue = sequenceMode?.renderQueue
        case .sequence:
            state.currentModeType = .montage
            appDelegate?.renderQueue = montageMode?.renderQueue
        }
    }
}

// Main content view that manages modes
struct AppContentView: View {
    @ObservedObject var state: HypnogramState
    weak var appDelegate: HypnographAppDelegate?
    @StateObject private var montageMode: MontageMode
    @StateObject private var sequenceMode: SequenceMode

    init(state: HypnogramState, appDelegate: HypnographAppDelegate?) {
        self.state = state
        self.appDelegate = appDelegate
        _montageMode = StateObject(wrappedValue: MontageMode(state: state))
        _sequenceMode = StateObject(wrappedValue: SequenceMode(state: state))
    }

    var currentMode: HypnographMode {
        switch state.currentModeType {
        case .montage:
            return montageMode
        case .sequence:
            return sequenceMode
        }
    }

    var body: some View {
        ContentView(
            state: state,
            renderQueue: currentMode.renderQueue,
            mode: currentMode
        )
        .onAppear {
            ModeHolder.shared.montageMode = montageMode
            ModeHolder.shared.sequenceMode = sequenceMode
            ModeHolder.shared.state = state
            ModeHolder.shared.appDelegate = appDelegate
            appDelegate?.renderQueue = montageMode.renderQueue
        }
    }
}

// Commands that access the modes
struct AppCommands: Commands {
    @ObservedObject private var state: HypnogramState
    @ObservedObject private var montageMode: MontageMode
    @ObservedObject private var sequenceMode: SequenceMode
    private weak var appDelegate: HypnographAppDelegate?
    private let cycleModeHandler: () -> Void

    init(
        state: HypnogramState,
        montageMode: MontageMode,
        sequenceMode: SequenceMode,
        appDelegate: HypnographAppDelegate?,
        cycleMode: @escaping () -> Void
    ) {
        _state = ObservedObject(initialValue: state)
        _montageMode = ObservedObject(initialValue: montageMode)
        _sequenceMode = ObservedObject(initialValue: sequenceMode)
        self.appDelegate = appDelegate
        self.cycleModeHandler = cycleMode
    }

    private var currentMode: HypnographMode {
        switch state.currentModeType {
        case .montage:
            return montageMode
        case .sequence:
            return sequenceMode
        }
    }
    
    private func selectOrToggleSolo(index: Int) {
        currentMode.selectOrToggleSolo(index: index)
    }

    var body: some Commands {
        // Remove "New Window" and the default "New" options
        CommandGroup(replacing: .newItem) { }

        // Add custom "New Hypnogram"
        CommandGroup(after: .newItem) {
            Button("New (random)") {
                currentMode.newRandomHypnogram()
            }
            .keyboardShortcut(.space, modifiers: [])
        }

        // Add custom Save behavior
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                currentMode.saveCurrentHypnogram()
            }
            .keyboardShortcut("s", modifiers: [.command])
        }

        CommandMenu("View") {
            Button("Montage Mode") {
                state.currentModeType = .montage
                appDelegate?.renderQueue = montageMode.renderQueue
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])

            Button("Sequence Mode") {
                state.currentModeType = .sequence
                appDelegate?.renderQueue = sequenceMode.renderQueue
            }
            .keyboardShortcut("2", modifiers: [.command, .shift])

            Divider()

            Button("Cycle Mode (Montage ⇄ Sequence)") {
                cycleModeHandler()
            }
            .keyboardShortcut("`", modifiers: [])
        }

        CommandMenu("Current") {
            Button("Cycle Global Effect") {
                currentMode.cycleGlobalEffect()
            }
            .keyboardShortcut("e", modifiers: [])

            Button("Cycle Source Effect") {
                currentMode.cycleSourceEffect()
            }
            .keyboardShortcut("f", modifiers: [])

            Button("Clear All Effects") {
                currentMode.clearAllEffects()
            }
            .keyboardShortcut("0", modifiers: [])

            Divider()

            // Mode-specific commands (injected by current mode)
            let modeCommands = currentMode.modeCommands()
            ForEach(Array(modeCommands.enumerated()), id: \.offset) { _, command in
                Button(command.title) {
                    command.action()
                }
                .keyboardShortcut(command.keyEquivalent, modifiers: command.modifiers)
            }

            Divider()

            // Global navigation & candidate commands
            Button("New Clip") {
                currentMode.nextCandidate()
            }
            .keyboardShortcut("n", modifiers: [])

            Button("Add Source") {
                currentMode.addSource()
            }
            .keyboardShortcut(".", modifiers: [])

            Button("Next Layer") {
                currentMode.acceptCandidate()
            }
            .keyboardShortcut(.return, modifiers: [])

            Button("> Next Source") {
                currentMode.nextSource()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("< Previous Source") {
                currentMode.previousSource()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Divider()

            ForEach(0..<5) { idx in
                Button("Select Source \(idx + 1)") {
                    selectOrToggleSolo(index: idx)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
            }

            Button("Delete Current Source") {
                currentMode.deleteCurrentSource()
            }
            .keyboardShortcut(.delete, modifiers: [])

            Divider()

            Button("Toggle HUD") {
                currentMode.toggleHUD()
            }
            .keyboardShortcut("h", modifiers: [])

            Button("Toggle Solo") {
                currentMode.toggleSolo()
            }
            .keyboardShortcut("s", modifiers: [])

            Button("Restart Session, Reloading Settings from File") {
                currentMode.reloadSettings()
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
