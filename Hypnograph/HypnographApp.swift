import SwiftUI
import AppKit
import AVFoundation

extension NSWindow {
    func makeHypnographBorderless(on screen: NSScreen, contentSize: CGSize) {
        let fullFrame = screen.frame
        let frame = fullFrame

        styleMask.remove(.titled)
        styleMask.remove(.closable)
        styleMask.remove(.miniaturizable)
        styleMask.remove(.resizable)

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

        queue.onAllJobsFinished = { [weak sender] in
            DispatchQueue.main.async {
                sender?.reply(toApplicationShouldTerminate: true)
            }
        }

        return .terminateLater
    }
}

// MARK: - Main App

@main
struct HypnographApp: App {
    @NSApplicationDelegateAdaptor(HypnographAppDelegate.self)
    private var appDelegate

    private let settings: Settings
    @StateObject private var state: HypnographState
    private let renderQueue: RenderQueue  // Not @StateObject - we don't want to trigger view updates
    @StateObject private var dreamMode: DreamMode
    @StateObject private var divineMode: DivineMode

    init() {
        Environment.ensureDefaultSettingsFileExists()

        let settingsURL = Environment.defaultSettingsURL

        let settings: Settings
        do {
            settings = try SettingsLoader.load(from: settingsURL)
            print("Loaded settings from \(settingsURL.path)")
        } catch {
            print("⚠️ Failed to load settings, using emergency fallback: \(error)")
            settings = Settings(
                outputFolder: "~/Movies/Hypnograph/Renders",
                sourceFolders: SourceFoldersParam.array([
                    "~/Movies/Hypnograph/sources"
                ]),
                watch: true,
                maxSourcesForNew: 3,
                outputHeight: 1080,
                outputSeconds: 30,
                outputWidth: 1920,
                snapshotsFolder: "~/Movies/Hypnograph/snapshots",
                activeLibrariesPerMode: [:]
            )
        }

        self.settings = settings
        let state = HypnographState(settings: settings)
        let renderQueue = RenderQueue()
        self.renderQueue = renderQueue

        GlobalRenderHooks.manager = state.renderHooks

        _state = StateObject(wrappedValue: state)
        _dreamMode = StateObject(wrappedValue: DreamMode(state: state, renderQueue: renderQueue))
        _divineMode = StateObject(wrappedValue: DivineMode(state: state, renderQueue: renderQueue))
    }

    func cycleMode() {
        switch state.currentModeType {
        case .dream:
            state.currentModeType = .divine
        case .divine:
            state.currentModeType = .dream
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch state.currentModeType {
                case .dream:
                    ContentView(
                        state: state,
                        renderQueue: renderQueue,
                        mode: dreamMode
                    )
                case .divine:
                    ContentView(
                        state: state,
                        renderQueue: renderQueue,
                        mode: divineMode
                    )
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    guard let window = NSApp.windows.first else { return }

                    let screens = NSScreen.screens
                    let targetScreen = (screens.count > 1 ? screens[1] : screens[0])

                    window.makeHypnographBorderless(
                        on: targetScreen,
                        contentSize: state.settings.outputSize
                    )
                    appDelegate.mainWindow = window
                }

                appDelegate.renderQueue = renderQueue
            }
        }
        .commands {
            AppCommands(
                state: state,
                dreamMode: dreamMode,
                divineMode: divineMode,
                appDelegate: appDelegate,
                cycleMode: cycleMode
            )
        }
    }
}

// MARK: - Commands

struct AppCommands: Commands {
    @ObservedObject private var state: HypnographState
    @ObservedObject private var dreamMode: DreamMode
    @ObservedObject private var divineMode: DivineMode
    private weak var appDelegate: HypnographAppDelegate?
    private let cycleModeHandler: () -> Void

    init(
        state: HypnographState,
        dreamMode: DreamMode,
        divineMode: DivineMode,
        appDelegate: HypnographAppDelegate?,
        cycleMode: @escaping () -> Void
    ) {
        _state = ObservedObject(initialValue: state)
        _dreamMode = ObservedObject(initialValue: dreamMode)
        _divineMode = ObservedObject(initialValue: divineMode)
        self.appDelegate = appDelegate
        self.cycleModeHandler = cycleMode
    }

    private var currentMode: any HypnographMode {
        switch state.currentModeType {
        case .dream:
            return dreamMode
        case .divine:
            return divineMode
        }
    }

    var body: some Commands {
        // Standard About panel with custom label
        CommandGroup(replacing: .appInfo) {
            Button("About Hypnograph") {
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

            Button("Install hypnograph CLI and Finder Action") {
                Environment.installCLI()
                Environment.installAutomatorQuickAction()
            }
        }

        CommandGroup(replacing: .newItem) { }

        CommandGroup(after: .newItem) {
            Button("New") {
                currentMode.new()
            }
            .keyboardShortcut(.space, modifiers: [])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                currentMode.save()
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("Save Snapshot") {
                // Only DreamMode supports snapshots
                if let dreamMode = currentMode as? DreamMode {
                    dreamMode.saveSnapshot()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Divider()

            Button("Cycle Mode") {
                cycleModeHandler()
            }
            .keyboardShortcut("`", modifiers: [])

            Button("Dream Mode") {
                state.currentModeType = .dream
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])

            Button("Divine Mode") {
                state.currentModeType = .divine
            }
            .keyboardShortcut("2", modifiers: [.command, .shift])

            Divider()

            Button {
                state.toggleWatchMode()
            } label: {
                Text(state.settings.watch ? "✓  Watch" : "Watch")
            }
            .keyboardShortcut("w", modifiers: [])
        }

        CommandMenu("Source Libraries") {
            let keys: [String] = {
                let order = state.settings.sourceLibraryOrder
                if !order.isEmpty {
                    return order
                } else {
                    return Array(state.settings.sourceLibraries.keys).sorted()
                }
            }()

            if keys.isEmpty {
                Text("No libraries configured")
                    .disabled(true)
            } else {
                ForEach(keys, id: \.self) { key in
                    Button {
                        state.toggleLibrary(key: key)
                    } label: {
                        Text(state.isLibraryActive(key: key) ? "✓  \(key)" : key)
                    }
                }

                Divider()

                Button("Use Default Only") {
                    state.useOnlyDefaultLibrary()
                }
            }
        }

        CommandMenu("Composition") {
            let modeCompositionCommands = currentMode.compositionCommands()
            if !modeCompositionCommands.isEmpty {
                ForEach(Array(modeCompositionCommands.enumerated()), id: \.offset) { _, command in
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

            ForEach(0..<9, id: \.self) { idx in
                Button("Select Source \(idx + 1)") {
                    currentMode.selectSource(index: idx)
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

            Button("Cycle Effect") {
                currentMode.cycleSourceEffect()
            }
            .keyboardShortcut("f", modifiers: [])

            Button("New Random Clip") {
                currentMode.newRandomClip()
            }
            .keyboardShortcut("n", modifiers: [])

            Divider()

            Button("Delete") {
                currentMode.deleteCurrentSource()
            }
            .keyboardShortcut(.delete, modifiers: [])

            Button("Add to Exclude List") {
                state.excludeCurrentSource()
            }
            .keyboardShortcut("x", modifiers: [])
        }
    }
}
