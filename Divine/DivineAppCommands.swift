import SwiftUI
import AppKit
import HypnoCore

struct DivineAppCommands: Commands {
    @ObservedObject private var state: DivineState
    @ObservedObject private var divine: Divine

    init(state: DivineState, divine: Divine) {
        _state = ObservedObject(initialValue: state)
        _divine = ObservedObject(initialValue: divine)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Divine") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            }
        }

        CommandGroup(after: .appSettings) {
            Button("Show Settings Folder") {
                DivineEnvironment.showSettingsFolderInFinder()
            }
        }

        CommandGroup(replacing: .newItem) { }

        CommandGroup(after: .newItem) {
            Button("New") {
                divine.new()
            }
            .keyboardShortcut("n", modifiers: [.command])
        }

        CommandGroup(replacing: .saveItem) { }

        CommandMenu("Sources") {
            Toggle("Images", isOn: Binding(
                get: { state.isMediaTypeActive(.images) },
                set: { _ in state.toggleMediaType(.images) }
            ))

            Toggle("Videos", isOn: Binding(
                get: { state.isMediaTypeActive(.videos) },
                set: { _ in state.toggleMediaType(.videos) }
            ))

            Divider()

            Button("Refresh Libraries") {
                Task {
                    await state.refreshAvailableLibraries()
                }
            }

            Divider()

            let photosLibraries = state.availableLibraries.filter { $0.type == .applePhotos }
            let folderLibraries = state.availableLibraries.filter { $0.type == .folders }

            if photosLibraries.isEmpty && folderLibraries.isEmpty {
                Text("No libraries configured")
                    .disabled(true)
            } else {
                if !photosLibraries.isEmpty {
                    Section("Apple Photos") {
                        let regularPhotosLibraries = photosLibraries.filter { $0.id != ApplePhotosLibraryKeys.photosCustom }

                        if let allItems = regularPhotosLibraries.first(where: { $0.id == ApplePhotosLibraryKeys.photosAll }) {
                            Toggle(allItems.displayName, isOn: Binding(
                                get: { state.isLibraryActive(key: allItems.id) },
                                set: { _ in state.toggleLibrary(key: allItems.id) }
                            ))
                        }

                        let customCount = state.customPhotosAssetIds.count
                        let isCustomActive = state.isLibraryActive(key: ApplePhotosLibraryKeys.photosCustom)
                        let customLabel = customCount > 0 ? "Custom Selection (\(customCount))" : "Custom Selection"

                        Toggle(customLabel, isOn: Binding(
                            get: { isCustomActive },
                            set: { newValue in
                                if newValue {
                                    state.showPhotosPicker = true
                                } else {
                                    state.toggleLibrary(key: ApplePhotosLibraryKeys.photosCustom)
                                }
                            }
                        ))
                        .keyboardShortcut("o", modifiers: [.command, .shift])

                        ForEach(regularPhotosLibraries.filter { $0.id != ApplePhotosLibraryKeys.photosAll }) { lib in
                            Toggle(lib.displayName, isOn: Binding(
                                get: { state.isLibraryActive(key: lib.id) },
                                set: { _ in state.toggleLibrary(key: lib.id) }
                            ))
                        }
                    }
                }

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
            divine.compositionMenu()
        }

        CommandMenu("Source") {
            divine.sourceMenu()
        }
    }
}
