import SwiftUI
import AppKit
import AVFoundation

extension NSWindow {
    func makeHypnographBorderless(on screen: NSScreen) {
        let fullFrame = screen.frame

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

        setFrame(fullFrame, display: true, animate: false)
        isMovable = false
    }
}

// MARK: - App Delegate

final class HypnographAppDelegate: NSObject, NSApplicationDelegate {
    weak var renderQueue: RenderQueue?
    weak var mainWindow: NSWindow?
    var gameControllerManager: GameControllerManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification authorization
        AppNotifications.requestAuthorization()

        // Request Photos library authorization and refresh hidden assets cache
        Task {
            let status = await ApplePhotos.shared.requestAuthorization()
            if status.canRead {
                let count = ApplePhotos.shared.refreshHiddenIdentifiersCache()
                if count > 0 {
                    print("ApplePhotos: Cached \(count) hidden asset identifiers")
                }
            }
        }
    }

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
    @StateObject private var dream: Dream
    @StateObject private var divine: Divine

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
                outputSeconds: 30,
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
        _dream = StateObject(wrappedValue: Dream(state: state, renderQueue: renderQueue))
        _divine = StateObject(wrappedValue: Divine(state: state, renderQueue: renderQueue))
    }

    func cycleModule() {
        switch state.currentModuleType {
        case .dream:
            state.currentModuleType = .divine
        case .divine:
            state.currentModuleType = .dream
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                state: state,
                renderQueue: renderQueue,
                dream: dream,
                divine: divine
            )
            .onAppear {
                DispatchQueue.main.async {
                    guard let window = NSApp.windows.first else { return }

                    let screens = NSScreen.screens
                    let targetScreen = (screens.count > 1 ? screens[1] : screens[0])

                    window.makeHypnographBorderless(on: targetScreen)
                    appDelegate.mainWindow = window
                }

                appDelegate.renderQueue = renderQueue

                // Initialize game controller support
                appDelegate.gameControllerManager = GameControllerManager(
                    state: state,
                    dream: dream,
                    divine: divine,
                    cycleModule: cycleModule
                )
            }
        }
        .commands {
            AppCommands(
                state: state,
                dream: dream,
                divine: divine,
                appDelegate: appDelegate,
                cycleModule: cycleModule
            )
        }
    }
}

// MARK: - Commands

struct AppCommands: Commands {
    @ObservedObject private var state: HypnographState
    @ObservedObject private var dream: Dream
    @ObservedObject private var divine: Divine
    private weak var appDelegate: HypnographAppDelegate?
    private let cycleModuleHandler: () -> Void

    init(
        state: HypnographState,
        dream: Dream,
        divine: Divine,
        appDelegate: HypnographAppDelegate?,
        cycleModule: @escaping () -> Void
    ) {
        _state = ObservedObject(initialValue: state)
        _dream = ObservedObject(initialValue: dream)
        _divine = ObservedObject(initialValue: divine)
        self.appDelegate = appDelegate
        self.cycleModuleHandler = cycleModule
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
                state.toggleHUD()
            }
            .keyboardShortcut("h", modifiers: [])

            Button("Toggle Info") {
                InfoWindowController.shared.toggle(sources: state.sources)
            }
            .keyboardShortcut("i", modifiers: [])

            Button(state.isPaused ? "Play" : "Pause") {
                state.togglePause()
            }
            .keyboardShortcut("p", modifiers: [])

            Button("Restart Session (Reload Settings)") {
                switch state.currentModuleType {
                case .dream: dream.reloadSettings()
                case .divine: divine.reloadSettings()
                }
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
                switch state.currentModuleType {
                case .dream: dream.new()
                case .divine: divine.new()
                }
            }
            .keyboardShortcut(.space, modifiers: [])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                switch state.currentModuleType {
                case .dream: dream.save()
                case .divine: divine.save()
                }
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("Save Snapshot") {
                // Only Dream supports snapshots
                dream.saveSnapshot()
            }
            .keyboardShortcut("s", modifiers: [])
        }

        CommandGroup(after: .sidebar) {
            Divider()

            Toggle("Dream", isOn: Binding(
                get: { state.currentModuleType == .dream },
                set: { if $0 { state.currentModuleType = .dream } }
            ))
            .keyboardShortcut("1", modifiers: [.command, .shift])

            Toggle("Divine", isOn: Binding(
                get: { state.currentModuleType == .divine },
                set: { if $0 { state.currentModuleType = .divine } }
            ))
            .keyboardShortcut("2", modifiers: [.command, .shift])

            Divider()

            Button("Cycle Module") {
                cycleModuleHandler()
            }
            .keyboardShortcut("~", modifiers: [])

            Divider()

            Toggle("Watch", isOn: Binding(
                get: { state.settings.watch },
                set: { _ in state.toggleWatchMode() }
            ))
            .keyboardShortcut("w", modifiers: [])
        }

        CommandMenu("Sources") {
            // Media type filters
            Toggle("Photos", isOn: Binding(
                get: { state.isMediaTypeActive(.photos) },
                set: { _ in state.toggleMediaType(.photos) }
            ))

            Toggle("Videos", isOn: Binding(
                get: { state.isMediaTypeActive(.videos) },
                set: { _ in state.toggleMediaType(.videos) }
            ))

            Divider()

            // Source libraries
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
                    Toggle(key, isOn: Binding(
                        get: { state.isLibraryActive(key: key) },
                        set: { _ in state.toggleLibrary(key: key) }
                    ))
                }
            }
        }

        CommandMenu("Composition") {
            // Dream-specific commands
            if state.currentModuleType == .dream {
                ForEach(Array(dream.compositionCommands().enumerated()), id: \.offset) { _, command in
                    Button(command.title) {
                        command.action()
                    }
                    .keyboardShortcut(command.keyEquivalent, modifiers: command.modifiers)
                }
                Divider()
            }

            Button("Cycle Global Effect") {
                dream.cycleGlobalEffect()
            }
            .keyboardShortcut("e", modifiers: [])

            Button("Add Source") {
                switch state.currentModuleType {
                case .dream: dream.addSource()
                case .divine: divine.addCard()
                }
            }
            .keyboardShortcut(".", modifiers: [])

            Button("> Next Source") {
                switch state.currentModuleType {
                case .dream: dream.nextSource()
                case .divine: divine.nextCard()
                }
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("< Previous Source") {
                switch state.currentModuleType {
                case .dream: dream.previousSource()
                case .divine: divine.previousCard()
                }
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            ForEach(0..<9, id: \.self) { idx in
                Button("Select Source \(idx + 1)") {
                    switch state.currentModuleType {
                    case .dream: dream.selectSource(index: idx)
                    case .divine: divine.selectCard(index: idx)
                    }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
            }

            Divider()

            Button("Clear All Effects") {
                dream.clearAllEffects()
            }
            .keyboardShortcut("0", modifiers: [])

            Button("Randomize Blend Modes") {
                state.randomizeBlendModes()
            }
            .keyboardShortcut(.space, modifiers: [.shift])

            Divider()

            // Aspect Ratio - flat in menu
            ForEach(AspectRatio.menuPresets, id: \.self) { ratio in
                Toggle(ratio.menuLabel, isOn: Binding(
                    get: { state.aspectRatio == ratio },
                    set: { if $0 { state.setAspectRatio(ratio) } }
                ))
            }

            Divider()

            // Resolution - flat in menu
            ForEach(OutputResolution.allCases, id: \.self) { resolution in
                Toggle(resolution.displayName, isOn: Binding(
                    get: { state.outputResolution == resolution },
                    set: { if $0 { state.setOutputResolution(resolution) } }
                ))
            }

            Divider()

            // Blend normalization toggle (for A/B testing)
            Toggle("Blend Normalization", isOn: Binding(
                get: { state.renderHooks.isNormalizationEnabled },
                set: { state.renderHooks.isNormalizationEnabled = $0 }
            ))
        }

        CommandMenu("Current Source") {
            // Dream-specific commands
            if state.currentModuleType == .dream {
                ForEach(Array(dream.sourceCommands().enumerated()), id: \.offset) { _, command in
                    Button(command.title) {
                        command.action()
                    }
                    .keyboardShortcut(command.keyEquivalent, modifiers: command.modifiers)
                }
                if !dream.sourceCommands().isEmpty {
                    Divider()
                }
            }

            Button("Rotate 90° Clockwise") {
                dream.rotateCurrentSource()
            }
            .keyboardShortcut("r", modifiers: [])

            Button("Cycle Effect") {
                dream.cycleSourceEffect()
            }
            .keyboardShortcut("f", modifiers: [])

            Button("New Random Clip") {
                switch state.currentModuleType {
                case .dream: dream.newRandomClip()
                case .divine: divine.newRandomCard()
                }
            }
            .keyboardShortcut("n", modifiers: [])

            Divider()

            Button("Delete") {
                switch state.currentModuleType {
                case .dream: dream.deleteCurrentSource()
                case .divine: divine.deleteCurrentCard()
                }
            }
            .keyboardShortcut(.delete, modifiers: [])

            Button("Add to Exclude List") {
                state.excludeCurrentSource()
            }
            .keyboardShortcut("x", modifiers: [.shift])

            Button("Mark for Deletion") {
                state.markCurrentSourceForDeletion()
            }
            .keyboardShortcut("d", modifiers: [.shift])

            Button("Toggle Favorite") {
                state.toggleCurrentSourceFavorite()
            }
            .keyboardShortcut("f", modifiers: [.shift])
        }
    }
}
