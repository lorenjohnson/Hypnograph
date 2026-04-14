import SwiftUI
import AppKit
import HypnoCore
import HypnoUI

// MARK: - App Shell

@main
struct HypnographApp: App {
    @NSApplicationDelegateAdaptor(HypnographAppDelegate.self)
    private var appDelegate

    private let settingsStore: StudioSettingsStore
    private let effectsComposerSettingsStore: EffectsComposerSettingsStore
    @StateObject private var state: HypnographState
    private let renderQueue: RenderEngine.ExportQueue  // Not @StateObject - we don't want to trigger view updates
    @StateObject private var studio: Studio

    init() {
        // Disable macOS window tabbing (must be set before any windows are created)
        NSWindow.allowsAutomaticWindowTabbing = false

        #if DEBUG
        Environment.performPendingDebugResetIfNeeded()
        #endif

        Environment.ensureDefaultSettingsFilesExist()

        let settingsStore = StudioSettingsStore()
        let effectsComposerSettingsStore = EffectsComposerSettingsStore()
        self.settingsStore = settingsStore
        self.effectsComposerSettingsStore = effectsComposerSettingsStore
        let coreConfig = HypnoCoreConfig(appSupportDirectory: Environment.appSupportDirectory)
        HypnoCoreConfig.shared = coreConfig
        ApplePhotosHooks.install()
        ExternalMediaLoadHarness.shared.installHookWrappersIfNeeded()

        let state = HypnographState(
            settingsStore: settingsStore,
            coreConfig: coreConfig
        )
        let renderQueue = RenderEngine.ExportQueue()
        renderQueue.onStatusMessage = { message in
            switch message {
            case "Rendering started", "Sequence render started":
                AppNotifications.show(message, flash: true, duration: 1.1)
            case let failure where failure.hasPrefix("Save failed:"):
                AppNotifications.show(failure, flash: false)
            default:
                break
            }
        }
        self.renderQueue = renderQueue

        _state = StateObject(wrappedValue: state)
        _studio = StateObject(wrappedValue: Studio(state: state, renderQueue: renderQueue))
    }

    var body: some Scene {
        WindowGroup("Hypnograph", id: "main") {
            ContentView(
                state: state,
                main: studio
            )
            .tint(.blue)
            .preferredColorScheme(.dark)
            .onAppear {
                DispatchQueue.main.async {
                    guard let window = NSApp.windows.first(where: { $0.title == "Hypnograph" })
                        ?? NSApp.mainWindow
                        ?? NSApp.windows.first(where: { $0.title != "About Hypnograph" })
                        ?? NSApp.windows.first else { return }
                    appDelegate.registerMainWindow(window)
                }

                appDelegate.renderQueue = renderQueue

                appDelegate.onPhotosAuthorization = { [weak state] in
                    Task { @MainActor in
                        await state?.refreshPhotosLibrariesAfterAuthorization()
                    }
                }

                // Wire up session-based unsaved changes check
                appDelegate.hasUnsavedEffectChanges = { [weak studio] in
                    guard let studio else { return false }
                    return studio.effectsSession.hasUnsavedChanges
                }

                // Wire up session-based save
                appDelegate.saveEffectSessions = { [weak studio] in
                    studio?.effectsSession.save()
                }

                // Wire up transport and panel-hide callbacks
                appDelegate.togglePlayPause = { [weak studio] in
                    studio?.activePlayer.isPaused.toggle()
                }
                appDelegate.saveSnapshotImage = { [weak studio] in
                    studio?.saveSnapshotImage()
                }
                appDelegate.hidePanelsNow = {
                    NotificationCenter.default.post(name: ContentView.studioHidePanelsNowNotification, object: nil)
                }
                appDelegate.isTypingActive = { [weak state] in
                    state?.isKeyboardTextInputActive ?? false
                }
                appDelegate.isKeyboardAccessibilityOverridesEnabled = { [weak state] in
                    state?.settings.keyboardAccessibilityOverridesEnabled ?? true
                }

                // Wire up panel state persistence
                appDelegate.savePanelState = { [weak studio] in
                    studio?.panels.saveToDisk()
                }
                appDelegate.setMainWindowFullScreenState = { [weak studio] isFullScreen in
                    studio?.panels.setMainWindowFullScreen(isFullScreen)
                }
                appDelegate.shouldRestoreMainWindowFullScreenState = { [weak studio] in
                    studio?.panels.mainWindowFullScreen ?? true
                }
                appDelegate.applyStoredMainWindowFullscreenPreferenceIfNeeded()

                // Wire up composition effect chain suspend (` key hold)
                appDelegate.setCompositionEffectSuspended = { [weak studio] suspended in
                    guard let studio, !studio.isLiveMode else { return }
                    studio.player.isCompositionEffectSuspended = suspended
                    studio.player.effectManager.isCompositionEffectSuspended = suspended
                }

                // Wire up flash solo (1-9 key hold)
                appDelegate.setFlashSolo = { [weak studio] sourceIndex in
                    guard let studio, !studio.isLiveMode else { return false }
                    // Only set flash solo if the source exists, otherwise ignore
                    if let index = sourceIndex {
                        guard index < studio.currentLayers.count else { return false }
                    }
                    studio.player.effectManager.setFlashSolo(sourceIndex)
                    return true
                }

                // Wire up 1-9 source selection (used by the flash-solo key monitor)
                appDelegate.selectSourceIndex = { [weak studio] index in
                    guard let studio, !studio.isLiveMode else { return }
                    guard index >= 0, index < studio.currentLayers.count else { return }
                    studio.selectSource(index)
                }

                // Wire up external file opening (hypnogram documents + media sources)
                appDelegate.openIncomingFiles = { [weak studio, weak state] urls in
                    Task { @MainActor in
                        let status = studio?.refreshPhotosStatus() ?? state?.refreshPhotosAuthorizationStatus()
                        if status?.canRead == true {
                            await state?.refreshPhotosLibrariesAfterAuthorization()
                        }
                    }

                    let hypnogramURLs = urls.filter { HypnogramFileStore.isSupportedExtension($0.pathExtension) }
                    if let url = hypnogramURLs.first {
                        guard let hypnogram = HypnogramFileStore.load(from: url) else {
                            AppNotifications.show("Failed to load hypnogram", flash: true)
                            return
                        }
                        guard studio?.openHypnogramAsWorkingDocument(hypnogram, sourceURL: url) != false else {
                            return
                        }
                    }

                    let mediaURLs = urls.filter { !HypnogramFileStore.isSupportedExtension($0.pathExtension) }
                    guard !mediaURLs.isEmpty else { return }
                    _ = studio?.addSourcesAsNewComposition(fromFileURLs: mediaURLs)
                }

                // Refresh source availability at startup. If Photos is already authorized,
                // run the stronger post-auth recovery path so an initial empty library
                // can settle before the user has to open Sources manually.
                Task {
                    let status = state.refreshPhotosAuthorizationStatus()
                    if status.canRead {
                        await state.refreshPhotosLibrariesAfterAuthorization()
                    } else {
                        await state.refreshAvailableLibraries()
                    }
                }

                // When transport keys override accessibility navigation, start with no focused control.
                DispatchQueue.main.async {
                    guard state.settings.keyboardAccessibilityOverridesEnabled else { return }
                    (appDelegate.mainWindow ?? NSApp.mainWindow ?? NSApp.windows.first)?.makeFirstResponder(nil)
                }
            }
            .onChange(of: settingsStore.value.keyboardAccessibilityOverridesEnabled) { _, isEnabled in
                guard isEnabled else { return }
                DispatchQueue.main.async {
                    (appDelegate.mainWindow ?? NSApp.mainWindow ?? NSApp.windows.first)?.makeFirstResponder(nil)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { @MainActor in
                    let status = state.refreshPhotosAuthorizationStatus()
                    if status.canRead {
                        await state.refreshPhotosLibrariesAfterAuthorization()
                    } else {
                        await state.refreshAvailableLibraries()
                    }
                }
            }
        }
        .commands {
            AppCommands(
                state: state,
                studio: studio
            )
        }

        SwiftUI.Settings {
            AppSettingsView(state: state, main: studio)
                .frame(minWidth: 420, idealWidth: 480, maxWidth: 560, minHeight: 380)
        }
        .windowStyle(.hiddenTitleBar)

        Window("About Hypnograph", id: "about") {
            AboutHypnographView()
        }
        .defaultSize(width: 720, height: 245)
        .windowResizability(.contentSize)

        Window("Effects Composer", id: "effectsComposer") {
            EffectsComposer(state: state, settingsStore: effectsComposerSettingsStore)
        }
        .defaultSize(width: 1320, height: 860)
    }
}
