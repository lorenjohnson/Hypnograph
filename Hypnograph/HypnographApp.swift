import SwiftUI
import AppKit
import AVFoundation
import HypnoCore
import HypnoRenderer

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
    weak var renderQueue: RenderEngine.ExportQueue?
    weak var mainWindow: NSWindow?
    var gameControllerManager: GameControllerManager?

    /// Callback to toggle clean screen (injected by app)
    var toggleCleanScreen: (() -> Void)?

    /// Callback to check if typing is active (injected by app)
    var isTypingActive: (() -> Bool)?

    /// Callback to open a recipe file (injected by app)
    var openRecipeFile: ((URL) -> Void)?

    /// Callback to check if any session has unsaved changes (injected by app)
    var hasUnsavedEffectChanges: (() -> Bool)?

    /// Callback to save all effect sessions (injected by app)
    var saveEffectSessions: (() -> Void)?


    /// Callback to save window state (injected by app)
    var saveWindowState: (() -> Void)?
    /// Event monitor for Tab key (workaround for SwiftUI menu shortcut not registering until menu opened)
    private var tabKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification authorization
        AppNotifications.requestAuthorization()

        // Install Tab key monitor to work around SwiftUI menu shortcut bug
        tabKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check for Tab key (keyCode 48) with no modifiers
            if event.keyCode == 48 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                // Don't intercept if user is typing in a text field
                if self?.isTypingActive?() == true {
                    return event
                }
                // Toggle clean screen
                self?.toggleCleanScreen?()
                return nil  // Consume the event
            }
            return event
        }

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
        if hasUnsavedEffectChanges?() == true {
            let alert = NSAlert()
            alert.messageText = "Save Effect Changes?"
            alert.informativeText = "You have unsaved effect changes. Would you like to save them before quitting?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                saveEffectSessions?()
            case .alertThirdButtonReturn:
                return .terminateCancel
            default:
                break
            }

            // Save window state before terminating
            saveWindowState?()
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

    /// Handle files opened via double-click or drag-drop onto the app
    func application(_ application: NSApplication, open urls: [URL]) {
        // Filter for supported recipe files
        let hypnogramURLs = urls.filter { RecipeStore.isSupportedExtension($0.pathExtension) }

        // Open the first hypnogram file
        if let url = hypnogramURLs.first {
            print("Hypnograph: Opening file \(url.lastPathComponent)")
            openRecipeFile?(url)
        }
    }
}

// MARK: - Main App

@main
struct HypnographApp: App {
    @NSApplicationDelegateAdaptor(HypnographAppDelegate.self)
    private var appDelegate

    private let settings: Settings
    @StateObject private var state: HypnographState
    private let renderQueue: RenderEngine.ExportQueue  // Not @StateObject - we don't want to trigger view updates
    @StateObject private var dream: Dream
    @StateObject private var divine: Divine

    init() {
        let coreConfig = HypnoCoreConfig(appSupportDirectory: Environment.appSupportDirectory)
        HypnoCoreConfig.shared = coreConfig
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
                snapshotsFolder: "~/Movies/Hypnograph/snapshots",
                activeLibrariesPerMode: [:]
            )
        }

        self.settings = settings
        let state = HypnographState(settings: settings, coreConfig: coreConfig)
        let renderQueue = RenderEngine.ExportQueue()
        renderQueue.onStatusMessage = { message in
            let duration: TimeInterval = (message == "Rendering started") ? 1.0 : 2.0
            AppNotifications.show(message, flash: true, duration: duration)
        }
        self.renderQueue = renderQueue

        _state = StateObject(wrappedValue: state)
        _dream = StateObject(wrappedValue: Dream(state: state, renderQueue: renderQueue))
        let divineState = DivineState(state: state)
        _divine = StateObject(wrappedValue: Divine(state: divineState))
    }

    func cycleModule() {
        switch state.currentModuleType {
        case .dream:
            state.currentModuleType = .divine
        case .divine:
            state.currentModuleType = .dream
        }
    }

    func sendToLivePlayer() {
        switch state.currentModuleType {
        case .dream:
            dream.sendToLivePlayer()
        case .divine:
            // Divine doesn't use recipes the same way, skip for now
            print("⚠️ Performance Display: Divine mode not supported yet")
        }
    }

    var body: some Scene {
        WindowGroup("Hypnograph", id: "main") {
            ContentView(
                state: state,
                dream: dream,
                divine: divine
            )
            .tint(.blue)
            .preferredColorScheme(.dark)
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

                // Wire up session-based unsaved changes check
                appDelegate.hasUnsavedEffectChanges = { [weak dream] in
                    guard let dream = dream else { return false }
                    // Check all sessions for unsaved changes
                    return dream.montagePlayer.effectsSession.hasUnsavedChanges ||
                           dream.sequencePlayer.effectsSession.hasUnsavedChanges ||
                           dream.livePlayer.effectsSession.hasUnsavedChanges
                }

                // Wire up session-based save
                appDelegate.saveEffectSessions = { [weak dream] in
                    dream?.montagePlayer.effectsSession.save()
                    dream?.sequencePlayer.effectsSession.save()
                    dream?.livePlayer.effectsSession.save()
                }

                // Wire up Tab key callbacks for clean screen toggle
                appDelegate.toggleCleanScreen = { [weak state] in
                    state?.windowState.toggleCleanScreen()
                }
                appDelegate.isTypingActive = { [weak state] in
                    state?.isTyping ?? false
                }

                // Wire up window state persistence
                appDelegate.saveWindowState = { [weak state] in
                    state?.saveWindowStateToDisk()
                }

                // Wire up recipe file opening
                appDelegate.openRecipeFile = { [weak dream] url in
                    guard let recipe = RecipeStore.load(from: url) else {
                        AppNotifications.show("Failed to load recipe", flash: true)
                        return
                    }
                    dream?.loadRecipe(recipe)
                    AppNotifications.show("Loaded \(url.lastPathComponent)", flash: true)
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
        .handlesExternalEvents(matching: ["main"])
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

    /// Whether a text field is currently being edited
    private var isTyping: Bool { state.isTyping }

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
            Button("Save Hypnogram") {
                switch state.currentModuleType {
                case .dream: dream.save()
                case .divine: divine.save()
                }
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("Save Hypnogram As…") {
                dream.saveAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Render Video and Save") {
                dream.renderAndSaveVideo()
            }

            Divider()

            Button("Open Hypnogram…") {
                dream.openRecipe()
            }
            .keyboardShortcut("o", modifiers: [.command])
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
                    get: { state.windowState.isVisible("hud") },
                    set: { _ in state.windowState.toggle("hud") }
                ))
                .keyboardShortcut("i", modifiers: [])
                .disabled(isTyping)

                Toggle("Effects Editor", isOn: Binding(
                    get: { state.windowState.isVisible("effectsEditor") },
                    set: { _ in state.windowState.toggle("effectsEditor") }
                ))
                .keyboardShortcut("e", modifiers: [])
                .disabled(isTyping || state.currentModuleType != .dream)

                Toggle("Hypnogram List", isOn: Binding(
                    get: { state.windowState.isVisible("hypnogramList") },
                    set: { _ in state.windowState.toggle("hypnogramList") }
                ))
                .keyboardShortcut("h", modifiers: [])
                .disabled(isTyping || state.currentModuleType != .dream)

                // Clean Screen: Tab key handled via NSEvent monitor in app delegate
                // (workaround for SwiftUI menu shortcut not registering until menu opened)
                Button("Clean Screen (Tab)") {
                    state.windowState.toggleCleanScreen()
                }
            }

            Divider()

            // Player Settings - only for Dream module
            Section("Player") {
                Toggle("Player Settings", isOn: Binding(
                    get: { state.windowState.isVisible("playerSettings") },
                    set: { _ in state.windowState.toggle("playerSettings") }
                ))
                .keyboardShortcut("p", modifiers: [])
                .disabled(isTyping || state.currentModuleType != .dream)
            }

            Divider()

            Section("Performance Display") {
                Toggle("Performance Preview", isOn: Binding(
                    get: { state.windowState.isVisible("performancePreview") },
                    set: { _ in state.windowState.toggle("performancePreview") }
                ))
                .keyboardShortcut("l", modifiers: [])
                .disabled(isTyping || state.currentModuleType != .dream)

                Toggle("Live Mode", isOn: Binding(
                    get: { dream.isLiveMode },
                    set: { _ in dream.toggleLiveMode() }
                ))
                .keyboardShortcut("l", modifiers: [.command])

                Toggle("External Monitor", isOn: Binding(
                    get: { dream.livePlayer.isVisible },
                    set: { _ in dream.livePlayer.toggle() }
                ))
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Send to Performance Display") {
                    // Get recipe from current module and send to performance display
                    // (auto-shows performance display if not visible)
                    switch state.currentModuleType {
                    case .dream:
                        dream.sendToLivePlayer()
                    case .divine:
                        print("⚠️ Performance Display: Divine mode not supported yet")
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Button("Reset Performance Display") {
                    dream.livePlayer.reset()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!dream.livePlayer.isVisible)
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
