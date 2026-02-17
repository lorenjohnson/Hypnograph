import SwiftUI
import AppKit
import AVFoundation
import HypnoCore
import HypnoUI

// MARK: - App Delegate

final class HypnographAppDelegate: NSObject, NSApplicationDelegate {
    weak var renderQueue: RenderEngine.ExportQueue?
    weak var mainWindow: NSWindow?

    /// Callback to toggle clean screen (injected by app)
    var toggleCleanScreen: (() -> Void)?

    /// Callback to toggle play/pause (injected by app)
    var togglePlayPause: (() -> Void)?

    /// Callback to toggle sidebars (injected by app)
    var toggleLeftSidebar: (() -> Void)?
    var toggleRightSidebar: (() -> Void)?

    /// Callback to check if typing is active (injected by app)
    var isTypingActive: (() -> Bool)?

    /// Callback for whether keyboard accessibility overrides are enabled (injected by app)
    var isKeyboardAccessibilityOverridesEnabled: (() -> Bool)?

    /// Callback to open a session file (injected by app)
    var openSessionFile: ((URL) -> Void)? {
        didSet {
            // Process any pending URL that arrived before callback was wired
            if let url = pendingSessionURL, openSessionFile != nil {
                pendingSessionURL = nil
                openSessionFile?(url)
            }
        }
    }

    /// URL received before openSessionFile callback was wired up
    private var pendingSessionURL: URL?

    /// Callback to check if any session has unsaved changes (injected by app)
    var hasUnsavedEffectChanges: (() -> Bool)?

    /// Callback to save all effect sessions (injected by app)
    var saveEffectSessions: (() -> Void)?

    /// Callback after Photos authorization completes (injected by app)
    var onPhotosAuthorization: (() -> Void)? {
        didSet {
            // If authorization completed before the callback was wired, fire it once.
            if pendingPhotosAuthorizationCallback, onPhotosAuthorization != nil {
                pendingPhotosAuthorizationCallback = false
                onPhotosAuthorization?()
            }
        }
    }

    /// Photos authorization can complete before the SwiftUI view hierarchy wires callbacks.
    private var pendingPhotosAuthorizationCallback = false

    @MainActor
    func photosAuthorizationDidComplete() {
        if let callback = onPhotosAuthorization {
            callback()
        } else {
            pendingPhotosAuthorizationCallback = true
        }
    }

    /// Callback to save window state (injected by app)
    var saveWindowState: (() -> Void)?

    /// Callback to suspend/resume global effects (injected by app)
    var setGlobalEffectSuspended: ((Bool) -> Void)?

    /// Callback to set flash solo (injected by app). Pass source index or nil to clear.
    /// Returns true if the source exists (or nil was passed), false if source index is out of range.
    var setFlashSolo: ((Int?) -> Bool)?

    /// Callback to select a source index (injected by app). Used for single-key navigation without
    /// relying on menu key equivalents (which can enter menu tracking and stall playback).
    var selectSourceIndex: ((Int) -> Void)?

    /// Event monitor for Tab key (workaround for SwiftUI menu shortcut not registering until menu opened)
    private var tabKeyMonitor: Any?

    /// Event monitor for Space key (play/pause transport)
    private var spaceKeyMonitor: Any?

    /// Event monitor for [ and ] keys (toggle sidebars)
    private var sidebarKeyMonitor: Any?

    /// Event monitor for ` key hold to suspend global effects
    private var globalKeyMonitor: Any?

    /// Event monitor for 1-9 keys hold to suspend source effects
    private var sourceKeyMonitor: Any?

    /// State for double-tap solo latch detection
    private var lastSourceKeyDownTime: TimeInterval = 0
    private var lastSourceKeyIndex: Int = -1
    private var isSoloLatched: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification authorization
        AppNotifications.configure(identity: .fromBundle())
        AppNotifications.requestAuthorization()

        // Install Space key monitor for play/pause transport
        spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            guard event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else {
                return event
            }

            if self.isTypingActive?() == true {
                return event
            }

            guard self.isKeyboardAccessibilityOverridesEnabled?() ?? true else {
                return event
            }

            guard let togglePlayPause = self.togglePlayPause else {
                return event
            }

            if event.isARepeat {
                return nil
            }

            togglePlayPause()
            return nil
        }

        // Install Tab key monitor for clean screen toggle (including Shift-Tab)
        tabKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isTab = event.keyCode == 48
            let isPlainTab = modifiers.isEmpty
            let isShiftTab = modifiers == .shift

            guard isTab, (isPlainTab || isShiftTab) else {
                return event
            }

            if self.isTypingActive?() == true {
                return event
            }

            guard self.isKeyboardAccessibilityOverridesEnabled?() ?? true else {
                return event
            }

            guard let toggleCleanScreen = self.toggleCleanScreen else {
                return event
            }

            if event.isARepeat {
                return nil
            }

            toggleCleanScreen()
            return nil
        }

        // Install [ and ] key monitor for toggling sidebars
        sidebarKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
            if self.isTypingActive?() == true { return event }
            if event.isARepeat { return event }

            switch event.charactersIgnoringModifiers {
            case "[":
                self.toggleLeftSidebar?()
                return nil
            case "]":
                self.toggleRightSidebar?()
                return nil
            default:
                return event
            }
        }

        // Install ` key monitor for hold-to-suspend global effects
        globalKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            // Only handle ` key with no modifiers
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  event.charactersIgnoringModifiers == "`" else {
                return event
            }
            // Don't intercept if user is typing
            if self?.isTypingActive?() == true {
                return event
            }
            // Suspend on keyDown, resume on keyUp
            self?.setGlobalEffectSuspended?(event.type == .keyDown)
            return event  // Don't consume - let SwiftUI handle the key press for layer selection
        }

        // Install 1-9 key monitor for hold-to-solo source (bypasses global effects, keeps source effect)
        // Double-tap to latch solo mode; any subsequent 1-9 key clears latch
        // keyCodes: 18=1, 19=2, 20=3, 21=4, 23=5, 22=6, 26=7, 28=8, 25=9
        let sourceKeyCodes: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
        sourceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self = self else { return event }
            // Only handle 1-9 keys with no modifiers
            guard let sourceIndex = sourceKeyCodes[event.keyCode],
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else {
                return event
            }
            // Don't intercept if user is typing
            if self.isTypingActive?() == true {
                return event
            }
            // Consume key repeats (prevents menu key equivalents from stalling playback while held).
            if event.isARepeat {
                return nil
            }

            let isDown = event.type == .keyDown
            let now = event.timestamp
            let doubleTapThreshold: TimeInterval = 0.3

            if isDown {
                // Keep layer selection responsive without letting the event fall through to the menu
                // system (menu tracking can stall playback while the key is held).
                self.selectSourceIndex?(sourceIndex)

                // Check for double-tap on same key
                let isDoubleTap = (sourceIndex == self.lastSourceKeyIndex) &&
                                  (now - self.lastSourceKeyDownTime < doubleTapThreshold)

                if isDoubleTap {
                    // Toggle latch state
                    self.isSoloLatched.toggle()
                    if self.isSoloLatched {
                        // Latch on: keep solo active (only if source exists)
                        if self.setFlashSolo?(sourceIndex) == true {
                            self.setGlobalEffectSuspended?(true)
                        } else {
                            self.isSoloLatched = false  // Source doesn't exist, cancel latch
                        }
                    } else {
                        // Latch off: clear solo
                        _ = self.setFlashSolo?(nil)
                        self.setGlobalEffectSuspended?(false)
                    }
                } else {
                    // Single tap or different key - if latched, any key clears latch
                    if self.isSoloLatched {
                        self.isSoloLatched = false
                        _ = self.setFlashSolo?(nil)
                        self.setGlobalEffectSuspended?(false)
                    } else {
                        // Normal hold behavior (only if source exists)
                        if self.setFlashSolo?(sourceIndex) == true {
                            self.setGlobalEffectSuspended?(true)
                        }
                    }
                }
                // Update tracking for next double-tap check
                self.lastSourceKeyDownTime = now
                self.lastSourceKeyIndex = sourceIndex
            } else {
                // keyUp: only clear if not latched
                if !self.isSoloLatched {
                    _ = self.setFlashSolo?(nil)
                    self.setGlobalEffectSuspended?(false)
                }
            }
            // Consume to prevent menu key equivalents (Select Layer 1-9) from entering menu tracking,
            // which can stall playback during flash-solo holds.
            return nil
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
                self?.photosAuthorizationDidComplete()
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
        // Filter for supported session files
        let sessionURLs = urls.filter { SessionStore.isSupportedExtension($0.pathExtension) }

        // Open the first session file
        if let url = sessionURLs.first {
            print("Hypnograph: Opening file \(url.lastPathComponent)")
            if let openSessionFile = openSessionFile {
                openSessionFile(url)
            } else {
                // Callback not wired yet - queue for later
                pendingSessionURL = url
            }
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
        // Disable macOS window tabbing (must be set before any windows are created)
        NSWindow.allowsAutomaticWindowTabbing = false

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
                    return dream.effectsSession.hasUnsavedChanges
                }

                // Wire up session-based save
                appDelegate.saveEffectSessions = { [weak dream] in
                    dream?.effectsSession.save()
                }

                // Wire up transport and clean screen callbacks
                appDelegate.togglePlayPause = { [weak dream] in
                    dream?.activePlayer.isPaused.toggle()
                }
                appDelegate.toggleCleanScreen = { [weak state] in
                    state?.windowState.toggleCleanScreen()
                }
                appDelegate.toggleLeftSidebar = { [weak state] in
                    _ = state?.windowState.toggle("leftSidebar")
                }
                appDelegate.toggleRightSidebar = { [weak state] in
                    _ = state?.windowState.toggle("rightSidebar")
                }
                appDelegate.isTypingActive = { [weak state] in
                    state?.isTyping ?? false
                }
                appDelegate.isKeyboardAccessibilityOverridesEnabled = { [weak state] in
                    state?.settings.keyboardAccessibilityOverridesEnabled ?? true
                }

                // Wire up window state persistence
                appDelegate.saveWindowState = { [weak state] in
                    state?.saveWindowStateToDisk()
                }

                // Wire up global effect suspend (` key hold)
                appDelegate.setGlobalEffectSuspended = { [weak dream] suspended in
                    guard let dream = dream, !dream.isLiveMode else { return }
                    dream.player.isGlobalEffectSuspended = suspended
                    dream.player.effectManager.isGlobalEffectSuspended = suspended
                }

                // Wire up flash solo (1-9 key hold)
                appDelegate.setFlashSolo = { [weak dream] sourceIndex in
                    guard let dream = dream, !dream.isLiveMode else { return false }
                    // Only set flash solo if the source exists, otherwise ignore
                    if let index = sourceIndex {
                        guard index < dream.player.layers.count else { return false }
                    }
                    dream.player.effectManager.setFlashSolo(sourceIndex)
                    return true
                }

                // Wire up 1-9 source selection (used by the flash-solo key monitor)
                appDelegate.selectSourceIndex = { [weak dream] index in
                    guard let dream = dream, !dream.isLiveMode else { return }
                    guard index >= 0, index < dream.player.layers.count else { return }
                    dream.player.selectSource(index)
                }

                // Wire up session file opening
                appDelegate.openSessionFile = { [weak dream] url in
                    guard let session = SessionStore.load(from: url) else {
                        AppNotifications.show("Failed to load session", flash: true)
                        return
                    }
                    dream?.appendSessionToHistory(session)
                    AppNotifications.show("Loaded \(url.lastPathComponent)", flash: true)
                }

                // Refresh available libraries (includes asset counts for menu)
                Task {
                    await state.refreshAvailableLibraries()
                }

                // When transport keys override accessibility navigation, start with no focused control.
                DispatchQueue.main.async {
                    guard state.settings.keyboardAccessibilityOverridesEnabled else { return }
                    (appDelegate.mainWindow ?? NSApp.mainWindow ?? NSApp.windows.first)?.makeFirstResponder(nil)
                }
            }
            .onChange(of: state.settings.keyboardAccessibilityOverridesEnabled) { _, isEnabled in
                guard isEnabled else { return }
                DispatchQueue.main.async {
                    (appDelegate.mainWindow ?? NSApp.mainWindow ?? NSApp.windows.first)?.makeFirstResponder(nil)
                }
            }
        }
        .handlesExternalEvents(matching: ["main"])
        .commands {
            AppCommands(
                state: state,
                dream: dream
            )
        }

        SwiftUI.Settings {
            AppSettingsView(state: state, dream: dream)
                .frame(minWidth: 320, idealWidth: 340, minHeight: 380)
        }

        Window("About Hypnograph", id: "about") {
            AboutHypnographView()
        }
        .defaultSize(width: 720, height: 245)
        .windowResizability(.contentSize)
    }
}
