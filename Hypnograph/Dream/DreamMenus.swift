//
//  DreamMenus.swift
//  Hypnograph
//
//  Menu builders and HUD items for Dream.
//  Separated from Dream.swift for better organization.
//

import SwiftUI
import AppKit
import HypnoCore
import HypnoUI

// MARK: - Dream Menu Extensions

extension Dream {

    // MARK: - HUD (deprecated - returns empty)

    func hudItems() -> [HUDItem] {
        // HUD removed in menu cleanup - this stub prevents compile errors
        return []
    }

    // MARK: - Menus

    /// Whether a text field is being edited - disables single-key shortcuts
    fileprivate var isTyping: Bool { state.isTyping }
    fileprivate var isMainWindowShortcutContext: Bool {
        windowBelongsToMain(NSApp.keyWindow)
    }
    fileprivate var disableMainWindowShortcuts: Bool {
        isTyping || !isMainWindowShortcutContext
    }

    @ViewBuilder
    func compositionMenu() -> some View {
        Button("Add Layer") { [self] in
            addSource()
        }
        .keyboardShortcut("n", modifiers: [.shift])
        .disabled(disableMainWindowShortcuts)

        Button("> Next Clip") { [self] in
            nextClip()
        }
        .keyboardShortcut(.rightArrow, modifiers: [])
        .disabled(disableMainWindowShortcuts)

        Button("< Previous Clip") { [self] in
            previousClip()
        }
        .keyboardShortcut(.leftArrow, modifiers: [])
        .disabled(disableMainWindowShortcuts)

        Divider()

        Button("Clear Current Layer Effect") { [self] in
            clearCurrentLayerEffect()
        }
        .keyboardShortcut("c", modifiers: [])
        .disabled(disableMainWindowShortcuts)

        Button("Clear All Effects") { [self] in
            clearAllEffects()
        }
        .keyboardShortcut("c", modifiers: [.control, .shift])
        .disabled(disableMainWindowShortcuts)

        Divider()

        Button("Cycle Effect Forward") { [self] in
            cycleEffect(direction: 1)
        }
        .keyboardShortcut("e", modifiers: [.command])

        Button("Cycle Effect Backward") { [self] in
            cycleEffect(direction: -1)
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])

        Button("Delete Clip") { [self] in
            deleteCurrentClip()
        }
        .keyboardShortcut(.delete, modifiers: [.command])
        .disabled(disableMainWindowShortcuts)

        Divider()

        // Aspect Ratio
        Section("Aspect Ratio") {
            ForEach(AspectRatio.menuPresets, id: \.displayString) { ratio in
                Toggle(ratio.menuLabel, isOn: Binding(
                    get: { [self] in activePlayer.config.aspectRatio == ratio },
                    set: { [self] in if $0 { setAspectRatio(ratio) } }
                ))
            }
        }

        // Output Resolution
        Section("Output Resolution") {
            ForEach(OutputResolution.allCases, id: \.self) { resolution in
                Toggle(resolution.displayName, isOn: Binding(
                    get: { [self] in activePlayer.config.playerResolution == resolution },
                    set: { [self] in if $0 { setOutputResolution(resolution) } }
                ))
            }
        }

        Divider()

        Button("> Next Layer") { [self] in
            nextSource()
        }
        .keyboardShortcut(.rightArrow, modifiers: [.option])
        .disabled(disableMainWindowShortcuts)

        Button("< Previous Layer") { [self] in
            previousSource()
        }
        .keyboardShortcut(.leftArrow, modifiers: [.option])
        .disabled(disableMainWindowShortcuts)

        ForEach(0..<9, id: \.self) { [self] idx in
            Button("Select Layer \(idx + 1)") { [self] in
                self.selectSource(index: idx)
            }
            .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
            .disabled(disableMainWindowShortcuts)
        }

        Button("Select Global Layer") { [self] in
            activePlayer.selectGlobalLayer()
        }
        .keyboardShortcut("`", modifiers: [])
        .disabled(disableMainWindowShortcuts)
    }

    @ViewBuilder
    func sourceMenu() -> some View {
        Button("Cycle Blend Mode") { [self] in
            cycleBlendMode()
        }
        .keyboardShortcut("m", modifiers: [])
        .disabled(disableMainWindowShortcuts)

        Button("New Random Clip") { [self] in
            newRandomClip()
        }
        .keyboardShortcut(".", modifiers: [])
        .disabled(disableMainWindowShortcuts)

        Divider()

        Button("Remove Layer") { [self] in
            removeCurrentLayer()
        }
        .keyboardShortcut(.delete, modifiers: [])
        .disabled(disableMainWindowShortcuts)

        Button("Add to Exclude List") { [self] in
            excludeCurrentSource()
        }
        .keyboardShortcut("x", modifiers: [.shift])
        .disabled(disableMainWindowShortcuts)

        Button("Add to Favorites") { [self] in
            favoriteCurrentSource()
        }
        .keyboardShortcut("f", modifiers: [.shift])
        .disabled(disableMainWindowShortcuts)
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
}
