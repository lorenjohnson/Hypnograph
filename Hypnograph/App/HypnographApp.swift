import SwiftUI
import AppKit
import HypnoCore
import HypnoUI

// MARK: - Main App

@main
struct HypnographApp: App {
    @NSApplicationDelegateAdaptor(HypnographAppDelegate.self)
    private var appDelegate

    private let settingsStore: MainSettingsStore
    private let appSettingsStore: AppSettingsStore
    private let effectsStudioSettingsStore: EffectsStudioSettingsStore
    @StateObject private var state: HypnographState
    private let renderQueue: RenderEngine.ExportQueue  // Not @StateObject - we don't want to trigger view updates
    @StateObject private var main: Main

    init() {
        // Disable macOS window tabbing (must be set before any windows are created)
        NSWindow.allowsAutomaticWindowTabbing = false

        Environment.ensureDefaultSettingsFilesExist()

        let settingsStore = MainSettingsStore()
        let appSettingsStore = AppSettingsStore()
        let effectsStudioSettingsStore = EffectsStudioSettingsStore()
        self.settingsStore = settingsStore
        self.appSettingsStore = appSettingsStore
        self.effectsStudioSettingsStore = effectsStudioSettingsStore
        let coreConfig = HypnoCoreConfig(appSupportDirectory: Environment.appSupportDirectory)
        HypnoCoreConfig.shared = coreConfig
        ApplePhotosHooks.install()
        ExternalMediaLoadHarness.shared.installHookWrappersIfNeeded()

        let state = HypnographState(
            settingsStore: settingsStore,
            appSettingsStore: appSettingsStore,
            coreConfig: coreConfig
        )
        let renderQueue = RenderEngine.ExportQueue()
        renderQueue.onStatusMessage = { message in
            let duration: TimeInterval = (message == "Rendering started") ? 1.0 : 2.0
            AppNotifications.show(message, flash: true, duration: duration)
        }
        self.renderQueue = renderQueue

        _state = StateObject(wrappedValue: state)
        _main = StateObject(wrappedValue: Main(state: state, renderQueue: renderQueue))
    }

    var body: some Scene {
        WindowGroup("Hypnograph", id: "main") {
            ContentView(
                state: state,
                main: main
            )
            .tint(.blue)
            .preferredColorScheme(.dark)
            .onAppear {
                DispatchQueue.main.async {
                    guard let window = NSApp.windows.first(where: { $0.title == "Hypnograph" })
                        ?? NSApp.mainWindow
                        ?? NSApp.windows.first(where: { $0.title != "About Hypnograph" })
                        ?? NSApp.windows.first else { return }
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
                appDelegate.hasUnsavedEffectChanges = { [weak main] in
                    guard let main = main else { return false }
                    return main.effectsSession.hasUnsavedChanges
                }

                // Wire up session-based save
                appDelegate.saveEffectSessions = { [weak main] in
                    main?.effectsSession.save()
                }

                // Wire up transport and clean screen callbacks
                appDelegate.togglePlayPause = { [weak main] in
                    main?.activePlayer.isPaused.toggle()
                }
                appDelegate.saveSnapshotImage = { [weak main] in
                    main?.saveSnapshotImage()
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
                    state?.appSettings.keyboardAccessibilityOverridesEnabled ?? true
                }

                // Wire up window state persistence
                appDelegate.saveWindowState = { [weak state] in
                    state?.saveWindowStateToDisk()
                }

                // Wire up global effect suspend (` key hold)
                appDelegate.setGlobalEffectSuspended = { [weak main] suspended in
                    guard let main = main, !main.isLiveMode else { return }
                    main.player.isGlobalEffectSuspended = suspended
                    main.player.effectManager.isGlobalEffectSuspended = suspended
                }

                // Wire up flash solo (1-9 key hold)
                appDelegate.setFlashSolo = { [weak main] sourceIndex in
                    guard let main = main, !main.isLiveMode else { return false }
                    // Only set flash solo if the source exists, otherwise ignore
                    if let index = sourceIndex {
                        guard index < main.player.layers.count else { return false }
                    }
                    main.player.effectManager.setFlashSolo(sourceIndex)
                    return true
                }

                // Wire up 1-9 source selection (used by the flash-solo key monitor)
                appDelegate.selectSourceIndex = { [weak main] index in
                    guard let main = main, !main.isLiveMode else { return }
                    guard index >= 0, index < main.player.layers.count else { return }
                    main.player.selectSource(index)
                }

                // Wire up external file opening (session documents + media sources)
                appDelegate.openIncomingFiles = { [weak main] urls in

                    let sessionURLs = urls.filter { SessionStore.isSupportedExtension($0.pathExtension) }
                    if let url = sessionURLs.first {
                        guard let session = SessionStore.load(from: url) else {
                            AppNotifications.show("Failed to load session", flash: true)
                            return
                        }
                        main?.appendSessionToHistory(session)
                        AppNotifications.show("Loaded \(url.lastPathComponent)", flash: true)
                    }

                    let mediaURLs = urls.filter { !SessionStore.isSupportedExtension($0.pathExtension) }
                    guard !mediaURLs.isEmpty else { return }
                    _ = main?.addSourcesAsNewClip(fromFileURLs: mediaURLs)
                }

                // Refresh available libraries (includes asset counts for menu)
                Task {
                    await state.refreshAvailableLibraries()
                }

                // When transport keys override accessibility navigation, start with no focused control.
                DispatchQueue.main.async {
                    guard state.appSettings.keyboardAccessibilityOverridesEnabled else { return }
                    (appDelegate.mainWindow ?? NSApp.mainWindow ?? NSApp.windows.first)?.makeFirstResponder(nil)
                }
            }
            .onChange(of: state.appSettings.keyboardAccessibilityOverridesEnabled) { _, isEnabled in
                guard isEnabled else { return }
                DispatchQueue.main.async {
                    (appDelegate.mainWindow ?? NSApp.mainWindow ?? NSApp.windows.first)?.makeFirstResponder(nil)
                }
            }
        }
        .commands {
            AppCommands(
                state: state,
                main: main
            )
        }

        SwiftUI.Settings {
            AppSettingsView(state: state, main: main)
                .frame(minWidth: 420, idealWidth: 480, maxWidth: 560, minHeight: 380)
        }
        .windowStyle(.hiddenTitleBar)

        Window("About Hypnograph", id: "about") {
            AboutHypnographView()
        }
        .defaultSize(width: 720, height: 245)
        .windowResizability(.contentSize)

        Window("Effect Studio", id: "effectsStudio") {
            EffectsStudio(state: state, settingsStore: effectsStudioSettingsStore)
        }
        .defaultSize(width: 1320, height: 860)
    }
}
