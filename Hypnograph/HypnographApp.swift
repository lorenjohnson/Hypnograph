import SwiftUI
import AppKit
import AVFoundation
import HypnoCore
import HypnoUI

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

    /// Callback after Photos authorization completes (injected by app)
    var onPhotosAuthorization: (() -> Void)?

    /// Callback to save window state (injected by app)
    var saveWindowState: (() -> Void)?
    /// Event monitor for Tab key (workaround for SwiftUI menu shortcut not registering until menu opened)
    private var tabKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification authorization
        AppNotifications.configure(identity: .fromBundle())
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
            await MainActor.run { [weak self] in
                self?.onPhotosAuthorization?()
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

    private let settingsStore: SettingsStore
    @StateObject private var state: HypnographState
    private let renderQueue: RenderEngine.ExportQueue  // Not @StateObject - we don't want to trigger view updates
    @StateObject private var dream: Dream

    init() {
        let coreConfig = HypnoCoreConfig(appSupportDirectory: Environment.appSupportDirectory)
        HypnoCoreConfig.shared = coreConfig
        ApplePhotosHooks.install()
        Environment.ensureDefaultSettingsFileExists()

        let settingsStore = SettingsStore()
        self.settingsStore = settingsStore

        let state = HypnographState(settingsStore: settingsStore, coreConfig: coreConfig)
        let renderQueue = RenderEngine.ExportQueue()
        renderQueue.onStatusMessage = { message in
            let duration: TimeInterval = (message == "Rendering started") ? 1.0 : 2.0
            AppNotifications.show(message, flash: true, duration: duration)
        }
        self.renderQueue = renderQueue

        _state = StateObject(wrappedValue: state)
        _dream = StateObject(wrappedValue: Dream(state: state, renderQueue: renderQueue))
    }

    var body: some Scene {
        WindowGroup("Hypnograph", id: "main") {
            ContentView(
                state: state,
                dream: dream
            )
            .tint(.blue)
            .preferredColorScheme(.dark)
            .onAppear {
                DispatchQueue.main.async {
                    guard let window = NSApp.windows.first else { return }

                    let screens = NSScreen.screens
                    // Main window stays on primary screen; live display uses external
                    let targetScreen = screens[0]

                    window.makeHypnographBorderless(on: targetScreen)
                    appDelegate.mainWindow = window
                }

                appDelegate.renderQueue = renderQueue

                appDelegate.onPhotosAuthorization = { [weak state] in
                    Task { @MainActor in
                        await state?.activatePhotosAllIfAvailable()
                        await state?.refreshAvailableLibraries()
                    }
                }

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
                    dream: dream
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
                appDelegate: appDelegate
            )
        }
    }
}

