//
//  AppCommands.swift
//  Hypnograph
//
//  App menu commands structure for the main menu bar.
//

import SwiftUI
import HypnoCore
import HypnoUI

struct AppCommands: Commands {
    @ObservedObject private var state: HypnographState
    @ObservedObject private var dream: Dream
    private weak var appDelegate: HypnographAppDelegate?

    /// Whether a text field is currently being edited
    private var isTyping: Bool { state.isTyping }

    init(
        state: HypnographState,
        dream: Dream,
        appDelegate: HypnographAppDelegate?
    ) {
        _state = ObservedObject(initialValue: state)
        _dream = ObservedObject(initialValue: dream)
        self.appDelegate = appDelegate
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

            Button("Clear Clip History") {
                dream.clearClipHistory()
            }
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
                dream.new()
            }
            .keyboardShortcut("n", modifiers: [.command])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Current") {
                dream.save()
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("Save Current As…") {
                dream.saveAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Save & Render Current") {
                dream.renderAndSaveVideo()
            }
            .keyboardShortcut("s", modifiers: [.option, .command])

            Divider()

            Button("Open Hypnogram…") {
                dream.openRecipe()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Toggle("Hypnogram List", isOn: Binding(
                get: { state.windowState.isVisible("hypnogramList") },
                set: { _ in state.windowState.toggle("hypnogramList") }
            ))
            .keyboardShortcut("h", modifiers: [])
            .disabled(isTyping)
        }

        CommandGroup(replacing: .sidebar) {
            Section("Overlays") {
                Toggle("Left Sidebar", isOn: Binding(
                    get: { state.windowState.isVisible("leftSidebar") },
                    set: { _ in state.windowState.toggle("leftSidebar") }
                ))
                .keyboardShortcut("[", modifiers: [])
                .disabled(isTyping)

                Toggle("Right Sidebar", isOn: Binding(
                    get: { state.windowState.isVisible("rightSidebar") },
                    set: { _ in state.windowState.toggle("rightSidebar") }
                ))
                .keyboardShortcut("]", modifiers: [])
                .disabled(isTyping)

                // Clean Screen: Tab key handled via NSEvent monitor in app delegate
                // (workaround for SwiftUI menu shortcut not registering until menu opened)
                Button("Clean Screen (Tab)") {
                    state.windowState.toggleCleanScreen()
                }
            }

            Divider()

            Section("Player") {
                Toggle("Watch", isOn: Binding(
                    get: { state.settings.watchMode },
                    set: { _ in state.toggleWatchMode() }
                ))
                .keyboardShortcut("w", modifiers: [])
                .disabled(isTyping)
            }

            if dream.isLiveModeAvailable {
                Divider()

                Section("Live Display") {
                    Toggle("Live Preview", isOn: Binding(
                        get: { state.windowState.isVisible("livePreview") },
                        set: { _ in state.windowState.toggle("livePreview") }
                    ))
                    .keyboardShortcut("l", modifiers: [])
                    .disabled(isTyping)

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

                    Button("Send to Live Display") {
                        dream.sendToLivePlayer()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])

                    Button("Reset Live Display") {
                        dream.livePlayer.reset()
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!dream.livePlayer.isVisible)
                }
            }

            Divider()

            Toggle("Full Screen", isOn: Binding(
                get: { NSApp.mainWindow?.styleMask.contains(.fullScreen) ?? false },
                set: { _ in NSApp.mainWindow?.toggleFullScreen(nil) }
            ))
            .keyboardShortcut("f", modifiers: [.control, .command])
        }

        CommandMenu("Sources") {
            sourcesMenu()
        }

        CommandMenu("Composition") {
            dream.compositionMenu()
        }

        CommandMenu("Layer") {
            dream.sourceMenu()
        }
    }

    @ViewBuilder
    private func sourcesMenu() -> some View {
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
            if !photosLibraries.isEmpty {
                Section("Apple Photos") {
                    let regularPhotosLibraries = photosLibraries.filter { $0.id != ApplePhotosLibraryKeys.photosCustom }

                    if let allItems = regularPhotosLibraries.first(where: { $0.id == "photos:all" }) {
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

                    ForEach(regularPhotosLibraries.filter { $0.id != "photos:all" }) { lib in
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
}
