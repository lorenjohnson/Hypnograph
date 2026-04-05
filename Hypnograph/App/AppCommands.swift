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
        case studio
        case effectsComposer
        case unknown
    }

    @SwiftUI.Environment(\.openWindow) private var openWindow
    @ObservedObject private var state: HypnographState
    @ObservedObject private var studio: Studio
    @ObservedObject private var windows: WindowStateController
    @ObservedObject private var appSettingsStore: AppSettingsStore

    /// Whether a text field is currently being edited
    private var isTyping: Bool { state.isKeyboardTextInputActive }
    private var isStudioWindowShortcutContext: Bool {
        activeWindowContext == .studio
    }

    init(
        state: HypnographState,
        studio: Studio
    ) {
        _state = ObservedObject(initialValue: state)
        _studio = ObservedObject(initialValue: studio)
        _windows = ObservedObject(initialValue: studio.windows)
        _appSettingsStore = ObservedObject(initialValue: state.appSettingsStore)
    }

    var body: some Commands {
        // Standard About panel with custom label
        CommandGroup(replacing: .appInfo) {
            Button("About Hypnograph") {
                openWindow(id: "about")
            }
        }

        CommandGroup(after: .appInfo) {
            if appSettingsStore.value.effectsComposerEnabled {
                Button("Open Effects Composer") {
                    openWindow(id: "effectsComposer")
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
            }
        }

        CommandGroup(replacing: .newItem) { }

        CommandGroup(after: .newItem) {
            Button("New") {
                studio.new()
            }
            .keyboardShortcut("n", modifiers: [.command])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Open Hypnogram…") {
                studio.openHypnogram()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Divider()

            Button("Save Current") {
                studio.save()
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("Save Current As…") {
                studio.saveAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Save & Render Current") {
                studio.renderAndSaveVideo()
            }
            .keyboardShortcut("s", modifiers: [.option, .command])

            Button("Favorite Current Hypnogram") {
                studio.favoriteCurrentHypnogram()
            }
            .keyboardShortcut("f", modifiers: [.command])

        }

        CommandGroup(replacing: .sidebar) {
            Section("Studio Panels") {
                Toggle("Composition", isOn: Binding(
                    get: { windows.isWindowVisible("compositionWindow") },
                    set: { _ in windows.toggleWindow("compositionWindow") }
                ))
                .keyboardShortcut("1", modifiers: [.option])
                .disabled(isTyping || !isStudioWindowShortcutContext)

                Toggle("Output Settings", isOn: Binding(
                    get: { windows.isWindowVisible("outputSettingsWindow") },
                    set: { _ in windows.toggleWindow("outputSettingsWindow") }
                ))
                .keyboardShortcut("2", modifiers: [.option])
                .disabled(isTyping || !isStudioWindowShortcutContext)

                Toggle("New Compositions", isOn: Binding(
                    get: { windows.isWindowVisible("newClipsWindow") },
                    set: { _ in windows.toggleWindow("newClipsWindow") }
                ))
                .keyboardShortcut("3", modifiers: [.option])
                .disabled(isTyping || !isStudioWindowShortcutContext)

                Toggle("Sources", isOn: Binding(
                    get: { windows.isWindowVisible("sourcesWindow") },
                    set: { _ in windows.toggleWindow("sourcesWindow") }
                ))
                .keyboardShortcut("4", modifiers: [.option])
                .disabled(isTyping || !isStudioWindowShortcutContext)

                Toggle("Effect Chains", isOn: Binding(
                    get: { windows.isWindowVisible("effectsWindow") },
                    set: { _ in windows.toggleWindow("effectsWindow") }
                ))
                .keyboardShortcut("5", modifiers: [.option])
                .disabled(isTyping || !isStudioWindowShortcutContext)

                Toggle("Hypnograms", isOn: Binding(
                    get: { windows.isWindowVisible("hypnogramList") },
                    set: { _ in windows.toggleWindow("hypnogramList") }
                ))
                .keyboardShortcut("6", modifiers: [.option])
                .disabled(isTyping || !isStudioWindowShortcutContext)

                Divider()

                Toggle("Auto-Hide Panels", isOn: Binding(
                    get: { appSettingsStore.value.autoHideWindowsEnabled },
                    set: { newValue in
                        appSettingsStore.update { $0.autoHideWindowsEnabled = newValue }
                    }
                ))

                Toggle("Hide Panels", isOn: Binding(
                    get: { windows.panelsHidden },
                    set: { newValue in
                        guard windows.panelsHidden != newValue else { return }
                        hidePanelsNowForActiveWindow()
                    }
                ))
                .keyboardShortcut(.tab, modifiers: [])

                #if DEBUG
                Divider()

                Button("Save Current Panel Layout as App Default") {
                    windows.saveToDisk()
                    do {
                        try Environment.saveCurrentWindowStateAsBundledDefault()
                        AppNotifications.show("Saved current panel layout as bundled default", flash: true)
                    } catch {
                        AppNotifications.show("Failed to save bundled panel layout", flash: true)
                        print("Failed to save bundled panel layout: \(error)")
                    }
                }
                #endif
            }

            if studio.isLiveModeAvailable {
                Divider()

                Section("Live Display") {
                    Toggle("Live Preview", isOn: Binding(
                        get: { windows.isWindowVisible("livePreview") },
                        set: { _ in windows.toggleWindow("livePreview") }
                    ))
                    .keyboardShortcut("w", modifiers: [])
                    .disabled(isTyping || !isStudioWindowShortcutContext)

                    Toggle("Live Mode", isOn: Binding(
                        get: { studio.isLiveMode },
                        set: { _ in studio.toggleLiveMode() }
                    ))
                    .keyboardShortcut("l", modifiers: [.command])

                    Toggle("External Monitor", isOn: Binding(
                        get: { studio.livePlayer.isVisible },
                        set: { _ in studio.livePlayer.toggle() }
                    ))
                    .keyboardShortcut("l", modifiers: [.command, .shift])

                    Button("Send to Live Display") {
                        studio.sendToLivePlayer()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])

                    Button("Reset Live Display") {
                        studio.livePlayer.reset()
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!studio.livePlayer.isVisible)
                }
            }

        }

        CommandMenu("Playback") {
            studio.playbackMenu()
        }

        CommandMenu("Composition") {
            studio.compositionMenu()
        }

        CommandMenu("Layer") {
            studio.sourceMenu()
        }

    }

    private func windowBelongsToStudio(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        if window.title == "Hypnograph" {
            return true
        }
        if let parent = window.parent {
            return windowBelongsToStudio(parent)
        }
        return false
    }

    private func windowBelongsToEffectsComposer(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        if window.title == "Effects Composer" {
            return true
        }
        if let parent = window.parent {
            return windowBelongsToEffectsComposer(parent)
        }
        return false
    }

    private var activeWindowContext: ActiveWindowContext {
        let candidates: [NSWindow?] = [NSApp.keyWindow, NSApp.mainWindow]
        for candidate in candidates {
            if windowBelongsToEffectsComposer(candidate) {
                return .effectsComposer
            }
            if windowBelongsToStudio(candidate) {
                return .studio
            }
        }
        return .unknown
    }

    private func hidePanelsNowForActiveWindow() {
        if activeWindowContext == .effectsComposer {
            NotificationCenter.default.post(name: .effectsComposerToggleCleanScreen, object: nil)
        } else {
            NotificationCenter.default.post(name: ContentView.studioHidePanelsNowNotification, object: nil)
        }
    }
}
