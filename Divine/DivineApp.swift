import SwiftUI
import AppKit
import HypnoCore
import HypnoUI

final class DivineAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppNotifications.configure(identity: .fromBundle())
        AppNotifications.requestAuthorization()
    }
}

@main
struct DivineApp: App {
    @NSApplicationDelegateAdaptor(DivineAppDelegate.self)
    private var appDelegate

    private let settingsStore: SettingsStore
    @StateObject private var state: DivineState
    @StateObject private var divine: Divine

    init() {
        let coreConfig = HypnoCoreConfig(appSupportDirectory: DivineEnvironment.appSupportDirectory)
        HypnoCoreConfig.shared = coreConfig
        ApplePhotosHooks.install()

        let settingsStore = SettingsStore()
        self.settingsStore = settingsStore

        let state = DivineState(settingsStore: settingsStore, coreConfig: coreConfig)
        _state = StateObject(wrappedValue: state)
        _divine = StateObject(wrappedValue: Divine(state: state))
    }

    var body: some Scene {
        WindowGroup("Divine", id: "main") {
            DivineContentView(state: state, divine: divine)
                .task {
                    let status = await ApplePhotos.shared.requestAuthorization()
                    if status.canRead {
                        let count = ApplePhotos.shared.refreshHiddenIdentifiersCache()
                        if count > 0 {
                            print("ApplePhotos: Cached \(count) hidden asset identifiers")
                        }
                    }
                    await MainActor.run {
                        state.rebuildActiveLibrary()
                        state.activatePhotosAllIfAvailable()
                    }
                    await state.refreshAvailableLibraries()
                }
        }
        .commands {
            DivineAppCommands(state: state, divine: divine)
        }
    }
}
