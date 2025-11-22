import SwiftUI
import AppKit
import AVFoundation

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
        // Normal window level so other apps can appear in front.
        level = .normal

        setFrame(frame, display: true, animate: false)
        isMovable = false
    }
}


// MARK: - App Delegate

final class HypnographAppDelegate: NSObject, NSApplicationDelegate {
    weak var renderQueue: RenderQueue?
    weak var mainWindow: NSWindow?

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

    // func applicationDidBecomeActive(_ notification: Notification) {
    //     mainWindow?.level = .statusBar
    // }

    // func applicationDidResignActive(_ notification: Notification) {
    //     mainWindow?.level = .normal
    // }
}

@main
struct HypnographApp: App {
    @NSApplicationDelegateAdaptor(HypnographAppDelegate.self)
    private var appDelegate

    private let settings: Settings
    @StateObject private var state: HypnogramState
    @StateObject private var montageMode: MontageMode
    @StateObject private var sequenceMode: SequenceMode
    @StateObject private var divineMode: DivineMode

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
                maxSources: 3,
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
        _divineMode = StateObject(wrappedValue: DivineMode(state: state))
    }

    var currentMode: HypnographMode {
        switch state.currentModeType {
        case .montage:
            return montageMode
        case .sequence:
            return sequenceMode
        case .divine:
            return divineMode
        }
    }

    func cycleMode() {
        switch state.currentModeType {
        case .montage:
            state.currentModeType = .sequence
            appDelegate.renderQueue = sequenceMode.renderQueue
        case .sequence:
            state.currentModeType = .divine
            appDelegate.renderQueue = divineMode.renderQueue
        case .divine:
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
                    appDelegate.mainWindow = window
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
                divineMode: divineMode,
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
    var divineMode: DivineMode?
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
        case .divine:
            return divineMode
        }
    }

    func cycleMode() {
        guard let state = state else { return }
        switch state.currentModeType {
        case .montage:
            state.currentModeType = .sequence
            appDelegate?.renderQueue = sequenceMode?.renderQueue
        case .sequence:
            state.currentModeType = .divine
            appDelegate?.renderQueue = divineMode?.renderQueue
        case .divine:
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
    @StateObject private var divineMode: DivineMode

    init(state: HypnogramState, appDelegate: HypnographAppDelegate?) {
        self.state = state
        self.appDelegate = appDelegate
        _montageMode = StateObject(wrappedValue: MontageMode(state: state))
        _sequenceMode = StateObject(wrappedValue: SequenceMode(state: state))
        _divineMode = StateObject(wrappedValue: DivineMode(state: state))
    }

    var currentMode: HypnographMode {
        switch state.currentModeType {
        case .montage:
            return montageMode
        case .sequence:
            return sequenceMode
        case .divine:
            return divineMode
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
            ModeHolder.shared.divineMode = divineMode
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
    @ObservedObject private var divineMode: DivineMode
    private weak var appDelegate: HypnographAppDelegate?
    private let cycleModeHandler: () -> Void

    init(
        state: HypnogramState,
        montageMode: MontageMode,
        sequenceMode: SequenceMode,
        divineMode: DivineMode,
        appDelegate: HypnographAppDelegate?,
        cycleMode: @escaping () -> Void
    ) {
        _state = ObservedObject(initialValue: state)
        _montageMode = ObservedObject(initialValue: montageMode)
        _sequenceMode = ObservedObject(initialValue: sequenceMode)
        _divineMode = ObservedObject(initialValue: divineMode)
        self.appDelegate = appDelegate
        self.cycleModeHandler = cycleMode
    }

    private var currentMode: HypnographMode {
        switch state.currentModeType {
        case .montage:
            return montageMode
        case .sequence:
            return sequenceMode
        case .divine:
            return divineMode
        }
    }

    private func selectOrToggleSolo(index: Int) {
        currentMode.selectOrToggleSolo(index: index)
    }

    var body: some Commands {
        // Standard About panel with custom label
        CommandGroup(replacing: .appInfo) {
            Button("About Hypnogram") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            }
        }

        // Items in the Hypnograph app menu (leftmost)
        CommandGroup(after: .appSettings) {
            Button("Toggle HUD") {
                currentMode.toggleHUD()
            }
            .keyboardShortcut("h", modifiers: [])

            Button("Restart Session (Reload Settings)") {
                currentMode.reloadSettings()
            }
            .keyboardShortcut("r", modifiers: [.command])

            Divider()

            Button("Show Settings Folder") {
                Environment.showSettingsFolderInFinder()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Install hypnograph CLI and Finder Action") {
                Environment.installCLI()
                Environment.installAutomatorQuickAction()
            }
        }

        // Remove "New Window" and the default "New" options
        CommandGroup(replacing: .newItem) { }

        // Add custom "New Hypnogram"
        CommandGroup(after: .newItem) {
            Button("New") {
                currentMode.new()
            }
            .keyboardShortcut(.space, modifiers: [])
        }

        // Add custom Save behavior
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                currentMode.save()
            }
            .keyboardShortcut("s", modifiers: [.command])
        }

        // Extend the default View menu with mode controls
        CommandGroup(after: .sidebar) {
            Divider()

            Button("Cycle Mode") {
                cycleModeHandler()
            }
            .keyboardShortcut("`", modifiers: [])

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

            Button("Divine Mode") {
                state.currentModeType = .divine
                appDelegate?.renderQueue = divineMode.renderQueue
            }
            .keyboardShortcut("3", modifiers: [.command, .shift])
        }

        CommandMenu("Composition") {
            let modeSourceCommands = currentMode.sourceCommands()
            if !modeSourceCommands.isEmpty {
                ForEach(Array(modeSourceCommands.enumerated()), id: \.offset) { _, command in
                    Button(command.title) {
                        command.action()
                    }
                    .keyboardShortcut(command.keyEquivalent, modifiers: command.modifiers)
                }

                Divider()
            }

            Button("Cycle Global Effect") {
                currentMode.cycleGlobalEffect()
            }
            .keyboardShortcut("e", modifiers: [])

            Button("Add Source") {
                currentMode.addSource()
            }
            .keyboardShortcut(".", modifiers: [])

            Button("> Next Source") {
                currentMode.nextSource()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("< Previous Source") {
                currentMode.previousSource()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            ForEach(0..<state.maxSources) { idx in
                Button("Select Source \(idx + 1)") {
                    selectOrToggleSolo(index: idx)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
            }

            Divider()

            Button("Clear All Effects") {
                currentMode.clearAllEffects()
            }
            .keyboardShortcut("0", modifiers: [])
        }

        CommandMenu("Current Source") {
            let modeSourceCommands = currentMode.sourceCommands()
            if !modeSourceCommands.isEmpty {
                ForEach(Array(modeSourceCommands.enumerated()), id: \.offset) { _, command in
                    Button(command.title) {
                        command.action()
                    }
                    .keyboardShortcut(command.keyEquivalent, modifiers: command.modifiers)
                }

                Divider()
            }

            Button("Toggle Solo") {
                currentMode.toggleSolo()
            }
            .keyboardShortcut("s", modifiers: [])

            Button("Cycle Effect") {
                currentMode.cycleSourceEffect()
            }
            .keyboardShortcut("f", modifiers: [])

            // Global navigation & candidate commands
            Button("New Candidate") {
                currentMode.nextCandidate()
            }
            .keyboardShortcut("n", modifiers: [])

            Button("Accept Candidate") {
                currentMode.acceptCandidate()
            }
            .keyboardShortcut(.return, modifiers: [])

            Divider()

            Button("Delete") {
                currentMode.deleteCurrentSource()
            }
            .keyboardShortcut(.delete, modifiers: [])

            Button("Add to Exclude List") {
                state.excludeCurrentSource()
            }
            .keyboardShortcut("x", modifiers: [])

            Divider()

            if state.currentModeType == .divine {
                Button("Re-deal Divine Cards") {
                    (currentMode as? DivineMode)?.redeal()
                }
                .keyboardShortcut("r", modifiers: [])
            }
        }
    }
}
