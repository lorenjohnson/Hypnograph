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
    @ObservedObject private var panels: PanelStateController
    @ObservedObject private var settingsStore: StudioSettingsStore

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
        _panels = ObservedObject(initialValue: studio.panels)
        _settingsStore = ObservedObject(initialValue: state.settingsStore)
    }

    var body: some Commands {
        // Standard About panel with custom label
        CommandGroup(replacing: .appInfo) {
            Button("About Hypnograph") {
                openWindow(id: "about")
            }
        }

        CommandGroup(after: .appInfo) {
            if settingsStore.value.effectsComposerEnabled {
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

            Button("New Composition") {
                studio.newComposition()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Open…") {
                studio.openHypnogram()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Divider()

            Button("Save") {
                studio.save()
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("Save As…") {
                studio.saveAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button("Save Composition") {
                studio.saveComposition()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button("Save Composition As…") {
                studio.saveCompositionAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .option, .shift])

            Divider()

            Button("Save & Render") {
                studio.renderAndSaveVideo()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])

        }

        CommandGroup(replacing: .sidebar) {
            Section("Panels") {
                ForEach(StudioPanelDescriptor.allCases) { descriptor in
                    Toggle(isOn: Binding(
                        get: { panels.isPanelVisible(descriptor.panelID) },
                        set: { _ in panels.togglePanel(descriptor.panelID) }
                    )) {
                        Label(descriptor.title, systemImage: descriptor.systemImage)
                    }
                    .keyboardShortcut(KeyEquivalent(descriptor.shortcutCharacter), modifiers: [.option])
                    .disabled(isTyping || !isStudioWindowShortcutContext)
                }

                Divider()

                Toggle("Hide Panels", isOn: Binding(
                    get: { panels.panelsHidden },
                    set: { newValue in
                        guard panels.panelsHidden != newValue else { return }
                        hidePanelsNowForActiveWindow()
                    }
                ))
                .keyboardShortcut(.tab, modifiers: [])

                Toggle("Auto-Hide Panels", isOn: Binding(
                    get: { settingsStore.value.autoHidePanelsEnabled },
                    set: { newValue in
                        settingsStore.update { $0.autoHidePanelsEnabled = newValue }
                    }
                ))

                #if DEBUG
                Divider()

                Button("Save Current Panel Layout as App Default") {
                    panels.saveToDisk()
                    do {
                        try Environment.saveCurrentPanelStateAsBundledDefault()
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
                        get: { panels.isPanelVisible("livePreviewPanel") },
                        set: { _ in panels.togglePanel("livePreviewPanel") }
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

        CommandMenu("Layers") {
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
