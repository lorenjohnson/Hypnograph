//
//  DreamMenus.swift
//  Hypnograph
//
//  Menu builders and HUD items for Dream.
//  Separated from Dream.swift for better organization.
//

import SwiftUI
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

    @ViewBuilder
    func compositionMenu() -> some View {
        Button("Cycle Effect Forward") { [self] in
            cycleEffect(direction: 1)
        }
        .keyboardShortcut("e", modifiers: [.command])

        Button("Cycle Effect Backward") { [self] in
            cycleEffect(direction: -1)
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])

        Button("Add Layer") { [self] in
            addSource()
        }
        .keyboardShortcut("n", modifiers: [.shift])

        Button("> Next Clip") { [self] in
            nextClip()
        }
        .keyboardShortcut(.rightArrow, modifiers: [])
        .disabled(isTyping)

        Button("< Previous Clip") { [self] in
            previousClip()
        }
        .keyboardShortcut(.leftArrow, modifiers: [])
        .disabled(isTyping)

        Divider()

        Button("> Next Layer") { [self] in
            nextSource()
        }
        .keyboardShortcut(.rightArrow, modifiers: [.option])
        .disabled(isTyping)

        Button("< Previous Layer") { [self] in
            previousSource()
        }
        .keyboardShortcut(.leftArrow, modifiers: [.option])
        .disabled(isTyping)

        ForEach(0..<9, id: \.self) { [self] idx in
            Button("Select Layer \(idx + 1)") { [self] in
                self.selectSource(index: idx)
            }
            .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
            .disabled(isTyping)
        }

        Button("Select Global Layer") { [self] in
            activePlayer.selectGlobalLayer()
        }
        .keyboardShortcut("`", modifiers: [])
        .disabled(isTyping)

        Divider()

        Button("Clear Current Layer Effect") { [self] in
            clearCurrentLayerEffect()
        }
        .keyboardShortcut("c", modifiers: [])
        .disabled(isTyping)

        Button("Clear All Effects") { [self] in
            clearAllEffects()
        }
        .keyboardShortcut("c", modifiers: [.control, .shift])

        Divider()

        Button("New") { [self] in
            new()
        }
        .keyboardShortcut("n", modifiers: [])
        .disabled(isTyping)

        Button("Delete Clip") { [self] in
            deleteCurrentClip()
        }
        .keyboardShortcut(.delete, modifiers: [.command])
        .disabled(isTyping)

        Divider()

        Button("Render Video") { [self] in
            renderAndSaveVideo()
        }

        Button("Favorite Hypnogram") { [self] in
            favoriteCurrentHypnogram()
        }
        .keyboardShortcut("f", modifiers: [.command])

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
    }

    @ViewBuilder
    func sourceMenu() -> some View {
        Button("Cycle Blend Mode") { [self] in
            cycleBlendMode()
        }
        .keyboardShortcut("m", modifiers: [])
        .disabled(isTyping)

        Button("New Random Clip") { [self] in
            newRandomClip()
        }
        .keyboardShortcut(".", modifiers: [])
        .disabled(isTyping)

        Divider()

        Button("Remove Layer") { [self] in
            removeCurrentLayer()
        }
        .keyboardShortcut(.delete, modifiers: [])
        .disabled(isTyping)

        Button("Add to Exclude List") { [self] in
            excludeCurrentSource()
        }
        .keyboardShortcut("x", modifiers: [.shift])

        Button("Add to Favorites") { [self] in
            favoriteCurrentSource()
        }
        .keyboardShortcut("f", modifiers: [.shift])
    }
}
