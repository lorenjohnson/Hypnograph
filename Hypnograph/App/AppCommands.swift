//
//  AppCommands.swift
//  Hypnograph
//
//  App menu commands structure for the main menu bar.
//

import SwiftUI
import AppKit
import HypnoCore
import HypnoUI

struct AppCommands: Commands {
    private enum ActiveWindowContext {
        case main
        case studio
        case unknown
    }

    @SwiftUI.Environment(\.openWindow) private var openWindow
    @ObservedObject private var state: HypnographState
    @ObservedObject private var main: Main

    /// Whether a text field is currently being edited
    private var isTyping: Bool { state.isKeyboardTextInputActive }
    private var isMainWindowShortcutContext: Bool {
        activeWindowContext == .main
    }

    init(
        state: HypnographState,
        main: Main
    ) {
        _state = ObservedObject(initialValue: state)
        _main = ObservedObject(initialValue: main)
    }

    var body: some Commands {
        // Standard About panel with custom label
        CommandGroup(replacing: .appInfo) {
            Button("About Hypnograph") {
                openWindow(id: "about")
            }
        }

        CommandGroup(after: .appInfo) {
            if state.appSettings.effectsStudioEnabled {
                Button("Open Effects Studio") {
                    openWindow(id: "effectsStudio")
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
            }
        }

        CommandGroup(replacing: .newItem) { }

        CommandGroup(after: .newItem) {
            Button("New") {
                main.new()
            }
            .keyboardShortcut("n", modifiers: [.command])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Open Hypnogram…") {
                main.openRecipe()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Divider()

            Button("Save Current") {
                main.save()
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("Save Current As…") {
                main.saveAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Save & Render Current") {
                main.renderAndSaveVideo()
            }
            .keyboardShortcut("s", modifiers: [.option, .command])

            Button("Favorite Current Hypnogram") {
                main.favoriteCurrentHypnogram()
            }
            .keyboardShortcut("f", modifiers: [.command])

            Divider()

            Toggle("Hypnogram List", isOn: Binding(
                get: { state.windowState.isVisible("hypnogramList") },
                set: { _ in state.windowState.toggle("hypnogramList") }
            ))
            .keyboardShortcut("h", modifiers: [])
            .disabled(isTyping || !isMainWindowShortcutContext)
        }

        CommandGroup(replacing: .sidebar) {
            Section("Overlays") {
                Toggle("Left Sidebar", isOn: Binding(
                    get: { state.windowState.isVisible("leftSidebar") },
                    set: { _ in state.windowState.toggle("leftSidebar") }
                ))
                .keyboardShortcut("[", modifiers: [])
                .disabled(isTyping || !isMainWindowShortcutContext)

                Toggle("Right Sidebar", isOn: Binding(
                    get: { state.windowState.isVisible("rightSidebar") },
                    set: { _ in state.windowState.toggle("rightSidebar") }
                ))
                .keyboardShortcut("]", modifiers: [])
                .disabled(isTyping || !isMainWindowShortcutContext)

                // Clean Screen: Tab key handled via NSEvent monitor in app delegate
                // (workaround for SwiftUI menu shortcut not registering until menu opened)
                Button("Clean Screen (Tab)") {
                    toggleCleanScreenForActiveWindow()
                }
            }

            Divider()

            Section("Player") {
                Toggle("Loop Current Clip", isOn: Binding(
                    get: { state.settings.playbackEndBehavior == .loopCurrentClip },
                    set: { state.setLoopCurrentClipMode($0) }
                ))
                .keyboardShortcut("l", modifiers: [])
                .disabled(isTyping || !isMainWindowShortcutContext)
            }

            if main.isLiveModeAvailable {
                Divider()

                Section("Live Display") {
                    Toggle("Live Preview", isOn: Binding(
                        get: { state.windowState.isVisible("livePreview") },
                        set: { _ in state.windowState.toggle("livePreview") }
                    ))
                    .keyboardShortcut("w", modifiers: [])
                    .disabled(isTyping || !isMainWindowShortcutContext)

                    Toggle("Live Mode", isOn: Binding(
                        get: { main.isLiveMode },
                        set: { _ in main.toggleLiveMode() }
                    ))
                    .keyboardShortcut("l", modifiers: [.command])

                    Toggle("External Monitor", isOn: Binding(
                        get: { main.livePlayer.isVisible },
                        set: { _ in main.livePlayer.toggle() }
                    ))
                    .keyboardShortcut("l", modifiers: [.command, .shift])

                    Button("Send to Live Display") {
                        main.sendToLivePlayer()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])

                    Button("Reset Live Display") {
                        main.livePlayer.reset()
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!main.livePlayer.isVisible)
                }
            }

        }

        CommandMenu("Sources") {
            sourcesMenu()
        }

        CommandMenu("Composition") {
            main.compositionMenu()
        }

        CommandMenu("Layer") {
            main.sourceMenu()
        }

    }

    private func windowBelongsToMain(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        if window.title == "Hypnograph" {
            return true
        }
        if let parent = window.parent {
            return windowBelongsToMain(parent)
        }
        return false
    }

    private func windowBelongsToStudio(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        if window.title == "Effect Studio" {
            return true
        }
        if let parent = window.parent {
            return windowBelongsToStudio(parent)
        }
        return false
    }

    private var activeWindowContext: ActiveWindowContext {
        let candidates: [NSWindow?] = [NSApp.keyWindow, NSApp.mainWindow]
        for candidate in candidates {
            if windowBelongsToStudio(candidate) {
                return .studio
            }
            if windowBelongsToMain(candidate) {
                return .main
            }
        }
        return .unknown
    }

    private func toggleCleanScreenForActiveWindow() {
        if activeWindowContext == .studio {
            NotificationCenter.default.post(name: .effectsStudioToggleCleanScreen, object: nil)
        } else {
            state.windowState.toggleCleanScreen()
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
