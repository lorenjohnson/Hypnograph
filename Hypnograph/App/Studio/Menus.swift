//
//  Menus.swift
//  Hypnograph
//
//  Menu builders and HUD items for Studio.
//  Separated from Studio.swift for better organization.
//

import SwiftUI
import AppKit
import HypnoCore
import HypnoUI

// MARK: - Studio Menu Extensions

extension Studio {

    // MARK: - Menus

    /// Whether a text field is being edited - disables single-key shortcuts
    fileprivate var isTyping: Bool { state.isKeyboardTextInputActive }
    fileprivate var isMainWindowShortcutContext: Bool {
        windowBelongsToMain(NSApp.keyWindow)
    }
    fileprivate var disableMainWindowShortcuts: Bool {
        isTyping || !isMainWindowShortcutContext
    }
    fileprivate var hasSelectedActualLayer: Bool {
        activePlayer.currentLayerIndex >= 0 && activePlayer.currentLayerIndex < activePlayer.layers.count
    }

    @ViewBuilder
    func playbackMenu() -> some View {
        Toggle("Loop Current Composition", isOn: Binding(
            get: { [self] in isLoopCurrentCompositionEnabled },
            set: { [self] in
                if $0 != isLoopCurrentCompositionEnabled {
                    toggleLoopCurrentCompositionMode()
                }
            }
        ))
        .keyboardShortcut("l", modifiers: [])
        .disabled(disableMainWindowShortcuts)

        Divider()

        Button("Next") { [self] in
            nextComposition()
        }
        .keyboardShortcut(.rightArrow, modifiers: [])
        .disabled(disableMainWindowShortcuts)

        Button("Previous") { [self] in
            previousComposition()
        }
        .keyboardShortcut(.leftArrow, modifiers: [])
        .disabled(disableMainWindowShortcuts)
    }

    @ViewBuilder
    func compositionMenu() -> some View {
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

        Button("Save as Favorite") { [self] in
            favoriteCurrentHypnogram()
        }
        .keyboardShortcut("f", modifiers: [.command])
        .disabled(disableMainWindowShortcuts)

        Divider()

        Button("Delete") { [self] in
            deleteCurrentComposition()
        }
        .keyboardShortcut(.delete, modifiers: [.command])
        .disabled(disableMainWindowShortcuts)
    }

    @ViewBuilder
    func sourceMenu() -> some View {
        Button("Add") { [self] in
            addSource()
        }
        .keyboardShortcut("n", modifiers: [.shift])
        .disabled(disableMainWindowShortcuts)

        Section("Current") {
            Button("Clear Effect") { [self] in
                clearCurrentLayerEffect()
            }
            .keyboardShortcut("c", modifiers: [])
            .disabled(disableMainWindowShortcuts || !hasSelectedActualLayer)

            Button("Cycle Blend Mode") { [self] in
                cycleBlendMode()
            }
            .keyboardShortcut("m", modifiers: [])
            .disabled(disableMainWindowShortcuts || !hasSelectedActualLayer)

            Button("Remove") { [self] in
                removeCurrentLayer()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(disableMainWindowShortcuts || !hasSelectedActualLayer)

            Button("New Random Source") { [self] in
                randomizeCurrentSource()
            }
            .keyboardShortcut(".", modifiers: [])
            .disabled(disableMainWindowShortcuts || !hasSelectedActualLayer)

            Button("Favorite Source") { [self] in
                favoriteCurrentSource()
            }
            .keyboardShortcut("f", modifiers: [.shift])
            .disabled(disableMainWindowShortcuts || !hasSelectedActualLayer)

            Button("Exclude Source") { [self] in
                excludeCurrentSource()
            }
            .keyboardShortcut("x", modifiers: [.shift])
            .disabled(disableMainWindowShortcuts || !hasSelectedActualLayer)
        }

        Divider()

        Section("Select") {
            Button("Next") { [self] in
                nextSource()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.option])
            .disabled(disableMainWindowShortcuts)

            Button("Previous") { [self] in
                previousSource()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.option])
            .disabled(disableMainWindowShortcuts)

            Button("Composition") { [self] in
                activePlayer.selectGlobalLayer()
            }
            .keyboardShortcut("`", modifiers: [])
            .disabled(disableMainWindowShortcuts)

            ForEach(0..<9, id: \.self) { [self] idx in
                Button("Select \(idx + 1)") { [self] in
                    self.selectSource(index: idx)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
                .disabled(disableMainWindowShortcuts)
            }
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
}
