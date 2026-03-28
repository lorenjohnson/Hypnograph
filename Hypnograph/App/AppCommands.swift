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
    }

    var body: some Commands {
        // Standard About panel with custom label
        CommandGroup(replacing: .appInfo) {
            Button("About Hypnograph") {
                openWindow(id: "about")
            }
        }

        CommandGroup(after: .appInfo) {
            if state.appSettings.effectsComposerEnabled {
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
                studio.openRecipe()
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

            Divider()

            Toggle("Hypnogram List", isOn: Binding(
                get: { windows.isWindowVisible("hypnogramList") },
                set: { _ in windows.toggleWindow("hypnogramList") }
            ))
            .keyboardShortcut("h", modifiers: [])
            .disabled(isTyping || !isStudioWindowShortcutContext)
        }

        CommandGroup(replacing: .sidebar) {
            Section("Studio Windows") {
                Toggle("Sources", isOn: Binding(
                    get: { windows.isWindowVisible("sourcesWindow") },
                    set: { _ in windows.toggleWindow("sourcesWindow") }
                ))
                .disabled(isTyping || !isStudioWindowShortcutContext)

                Toggle("New Clips", isOn: Binding(
                    get: { windows.isWindowVisible("newClipsWindow") },
                    set: { _ in windows.toggleWindow("newClipsWindow") }
                ))
                .disabled(isTyping || !isStudioWindowShortcutContext)

                Toggle("Output Settings", isOn: Binding(
                    get: { windows.isWindowVisible("outputSettingsWindow") },
                    set: { _ in windows.toggleWindow("outputSettingsWindow") }
                ))
                .disabled(isTyping || !isStudioWindowShortcutContext)

                Toggle("Composition", isOn: Binding(
                    get: { windows.isWindowVisible("compositionWindow") },
                    set: { _ in windows.toggleWindow("compositionWindow") }
                ))
                .disabled(isTyping || !isStudioWindowShortcutContext)

                Toggle("Effects", isOn: Binding(
                    get: { windows.isWindowVisible("effectsWindow") },
                    set: { _ in windows.toggleWindow("effectsWindow") }
                ))
                .disabled(isTyping || !isStudioWindowShortcutContext)

                // Clean Screen: Tab key handled via NSEvent monitor in app delegate
                // (workaround for SwiftUI menu shortcut not registering until menu opened)
                Button("Clean Screen (Tab)") {
                    toggleCleanScreenForActiveWindow()
                }
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

    private func toggleCleanScreenForActiveWindow() {
        if activeWindowContext == .effectsComposer {
            NotificationCenter.default.post(name: .effectsComposerToggleCleanScreen, object: nil)
        } else {
            windows.toggleCleanScreen()
        }
    }
}
