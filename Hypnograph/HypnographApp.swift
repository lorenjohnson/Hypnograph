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

    /// Callback to check if autosave is enabled (injected by app)
    var isAutosaveEnabled: (() -> Bool)?

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
        // Check for unsaved effect changes when autosave is disabled
        let autosaveOn = isAutosaveEnabled?() ?? true
        if !autosaveOn && EffectConfigLoader.hasUnsavedChanges {
            // Show save prompt
            let alert = NSAlert()
            alert.messageText = "Save Effect Changes?"
            alert.informativeText = "You have unsaved effect parameter changes. Would you like to save them before quitting?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                // Save
                EffectConfigLoader.save()
                print("Hypnograph: Saved effect changes before quit")
            case .alertSecondButtonReturn:
                // Don't save - continue to quit
                break
            case .alertThirdButtonReturn:
                // Cancel - don't quit
                return .terminateCancel
            default:
                break
            }
        }

        // Check for active render jobs
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
                sources: SourcesParam.array([
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

    func sendToPerformanceDisplay() {
        switch state.currentModuleType {
        case .dream:
            dream.sendToPerformanceDisplay()
        case .divine:
            // Divine doesn't use recipes the same way, skip for now
            print("⚠️ Performance Display: Divine mode not supported yet")
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
                    // Main window stays on primary screen; performance display uses external
                    let targetScreen = screens[0]

                    window.makeHypnographBorderless(on: targetScreen)
                    appDelegate.mainWindow = window
                }

                appDelegate.renderQueue = renderQueue

                // Wire up autosave callbacks
                appDelegate.isAutosaveEnabled = { [weak state] in
                    state?.settings.effectsAutosave ?? true
                }
                EffectConfigLoader.isAutosaveEnabled = { [weak state] in
                    state?.settings.effectsAutosave ?? true
                }

                // Initialize game controller support
                appDelegate.gameControllerManager = GameControllerManager(
                    state: state,
                    dream: dream,
                    divine: divine,
                    cycleModule: cycleModule
                )

                // Refresh available libraries (includes asset counts for menu)
                Task {
                    await state.refreshAvailableLibraries()
                }
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

    /// Whether a text field is currently being edited (from TextFieldFocusMonitor)
    private var isTyping: Bool { state.textFieldFocusMonitor.isEditing }

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
            Button(dream.activePlayer.isPaused ? "Play" : "Pause") {
                dream.activePlayer.isPaused.toggle()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(isTyping)

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
            .keyboardShortcut("n", modifiers: [.command])
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
                dream.saveSnapshot()
            }
            .keyboardShortcut("s", modifiers: [])
            .disabled(isTyping)

            Divider()

            Button("Open Hypnogram…") {
                dream.openRecipe()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Save Recipe…") {
                dream.saveRecipe()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
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
            .disabled(isTyping)

            Divider()

            Toggle("Watch", isOn: Binding(
                get: { state.settings.watch },
                set: { _ in state.toggleWatchMode() }
            ))
            .keyboardShortcut("w", modifiers: [])
            .disabled(isTyping)

            Divider()

            Section("Overlays") {
                Toggle("Info HUD", isOn: Binding(
                    get: { dream.activePlayer.isHUDVisible },
                    set: { dream.activePlayer.isHUDVisible = $0 }
                ))
                .keyboardShortcut("i", modifiers: [])
                .disabled(isTyping)

                Toggle("Effects Editor", isOn: Binding(
                    get: { dream.activePlayer.isEffectsEditorVisible },
                    set: { dream.activePlayer.isEffectsEditorVisible = $0 }
                ))
                .keyboardShortcut("e", modifiers: [])
                .disabled(isTyping)

                Toggle("Hypnogram List", isOn: $state.isHypnogramListVisible)
                    .keyboardShortcut("h", modifiers: [])
                    .disabled(isTyping || state.currentModuleType != .dream)
            }

            Divider()

            // Player Settings - only for Dream module
            Section("Player") {
                Toggle("Player Settings", isOn: Binding(
                    get: { dream.activePlayer.isPlayerSettingsVisible },
                    set: { dream.activePlayer.isPlayerSettingsVisible = $0 }
                ))
                .keyboardShortcut("p", modifiers: [])
                .disabled(isTyping || state.currentModuleType != .dream)
            }

            Divider()

            Section("Performance Display") {
                Toggle("Performance Preview", isOn: $state.isPerformancePreviewVisible)
                    .keyboardShortcut("l", modifiers: [])
                    .disabled(isTyping)

                Toggle("Live Mode", isOn: Binding(
                    get: { dream.isLiveMode },
                    set: { _ in dream.togglePerformanceMode() }
                ))
                .keyboardShortcut("l", modifiers: [.command])

                Toggle("External Monitor", isOn: Binding(
                    get: { dream.performanceDisplay.isVisible },
                    set: { _ in dream.performanceDisplay.toggle() }
                ))
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Send to Performance Display") {
                    // Get recipe from current module and send to performance display
                    // (auto-shows performance display if not visible)
                    switch state.currentModuleType {
                    case .dream:
                        dream.sendToPerformanceDisplay()
                    case .divine:
                        print("⚠️ Performance Display: Divine mode not supported yet")
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Button("Reset Performance Display") {
                    dream.performanceDisplay.reset()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!dream.performanceDisplay.isVisible)
            }
        }

        CommandMenu("Sources") {
            // Media type filters
            Toggle("Images", isOn: Binding(
                get: { state.isMediaTypeActive(.images) },
                set: { _ in state.toggleMediaType(.images) }
            ))

            Toggle("Videos", isOn: Binding(
                get: { state.isMediaTypeActive(.videos) },
                set: { _ in state.toggleMediaType(.videos) }
            ))

            Divider()

            let photosLibraries = state.availableLibraries.filter { $0.type == .applePhotos }
            let folderLibraries = state.availableLibraries.filter { $0.type == .folders }

            if photosLibraries.isEmpty && folderLibraries.isEmpty {
                Text("No libraries configured")
                    .disabled(true)
            } else {
                // Apple Photos section
                if !photosLibraries.isEmpty {
                    Section("Apple Photos") {
                        // Filter out Custom Selection from regular library list (handled separately)
                        let regularPhotosLibraries = photosLibraries.filter { $0.id != HypnographState.photosCustomKey }

                        // "All Items" first (if present)
                        if let allItems = regularPhotosLibraries.first(where: { $0.id == "photos:all" }) {
                            Toggle(allItems.displayName, isOn: Binding(
                                get: { state.isLibraryActive(key: allItems.id) },
                                set: { _ in state.toggleLibrary(key: allItems.id) }
                            ))
                        }

                        // Custom Selection right after All Items
                        let customCount = state.customPhotosAssetIds.count
                        let isCustomActive = state.isLibraryActive(key: HypnographState.photosCustomKey)
                        let customLabel = customCount > 0 ? "Custom Selection (\(customCount))" : "Custom Selection"

                        Toggle(customLabel, isOn: Binding(
                            get: { isCustomActive },
                            set: { newValue in
                                if newValue {
                                    // Turning ON: show picker first
                                    state.showPhotosPicker = true
                                } else {
                                    // Turning OFF: just deactivate
                                    state.toggleLibrary(key: HypnographState.photosCustomKey)
                                }
                            }
                        ))
                        .keyboardShortcut("o", modifiers: [.command, .shift])

                        // Rest of the albums (excluding "All Items" which is already shown)
                        ForEach(regularPhotosLibraries.filter { $0.id != "photos:all" }) { lib in
                            Toggle(lib.displayName, isOn: Binding(
                                get: { state.isLibraryActive(key: lib.id) },
                                set: { _ in state.toggleLibrary(key: lib.id) }
                            ))
                        }
                    }
                }

                // Folder-based libraries section
                if !folderLibraries.isEmpty {
                    Section("Folders") {
                        ForEach(folderLibraries) { lib in
                            Toggle(lib.displayName, isOn: Binding(
                                get: { state.isLibraryActive(key: lib.id) },
                                set: { _ in state.toggleLibrary(key: lib.id) }
                            ))
                        }
                    }
                }
            }
        }

        CommandMenu("Composition") {
            switch state.currentModuleType {
            case .dream:
                dream.compositionMenu()
            case .divine:
                divine.compositionMenu()
            }
        }

        CommandMenu("Source") {
            switch state.currentModuleType {
            case .dream:
                dream.sourceMenu()
            case .divine:
                divine.sourceMenu()
            }
        }

    }
}
