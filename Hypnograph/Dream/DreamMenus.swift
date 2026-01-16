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

    // MARK: - HUD

    func hudItems() -> [HUDItem] {
        var items: [HUDItem] = []

        // Header
        items.append(.text("Hypnograph", order: 10, font: .headline))
        items.append(.text("Dream: \(isLiveMode ? "Live" : "Preview")", order: 11, font: .subheadline))
        items.append(.padding(8, order: 15))

        // Queue status
        if renderQueue.activeJobs > 0 {
            items.append(.text("Queue: \(renderQueue.activeJobs)", order: 20, font: .subheadline))
        } else {
            items.append(.text("Queue: 0", order: 20, font: .caption))
        }
        items.append(.padding(8, order: 21))

        // Layer info (Global or Source X of Y)
        items.append(.text(activePlayer.editingLayerDisplay, order: 22))
        items.append(.text("Effect (E): \(activeEffectManager.effectName(for: activePlayer.currentSourceIndex))", order: 23))

        // Source-specific info (only when on a source layer, not global)
        if !activePlayer.isOnGlobalLayer {
            items.append(.text("Blend mode (M): \(currentBlendModeDisplayName())", order: 26))
            if let clip = activePlayer.currentVideoClip {
                items.append(.text("Layer clip: \(String(format: "%.1fs", clip.duration.seconds))", order: 27))
            }

        }

        items.append(.padding(16, order: 39))

        // Keyboard hints
        items.append(.text("Shortcuts", order: 40, font: .subheadline))
        items.append(.text(". = New clip | M = Blend | Delete = Mark for deletion", order: 41))
        items.append(.text("Cmd+E = Cycle effect | C = Clear layer | Ctrl+Shift+C = Clear all", order: 42))
        items.append(.text("E = Effects editor | ` = Global | 1-9 = Source", order: 43))
        items.append(.text("Left/Right = Navigate clips | Opt+Left/Right = Navigate layers", order: 44))
        items.append(.text("N = New | Shift+N = Add source | Opt+Delete = Remove layer | Cmd+Delete = Delete clip", order: 45))
        items.append(.text("Cmd+S = Save | Cmd+F = Favorite hypnogram", order: 46))
        items.append(.text("Shift+X/D/F = Exclude/Delete/Favorite source", order: 47))

        return items
    }

    // MARK: - Menus

    /// Whether a text field is being edited - disables single-key shortcuts
    fileprivate var isTyping: Bool { state.isTyping }

    @ViewBuilder
    func compositionMenu() -> some View {
        Button("Toggle Live Mode (Preview/Live)") { [self] in
            toggleLiveMode()
        }
        .disabled(isTyping)

        Divider()

        Button("Cycle Effect Forward") { [self] in
            cycleEffect(direction: 1)
        }
        .keyboardShortcut("e", modifiers: [.command])

        Button("Cycle Effect Backward") { [self] in
            cycleEffect(direction: -1)
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])

        Button("Add Source") { [self] in
            addSource()
        }
        .keyboardShortcut("n", modifiers: [.shift])

        // Only use arrow shortcuts when effects editor is closed (otherwise they adjust params)
        if !state.windowState.isVisible("effectsEditor") {
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

            Button("> Next Source") { [self] in
                nextSource()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.option])
            .disabled(isTyping)

            Button("< Previous Source") { [self] in
                previousSource()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.option])
            .disabled(isTyping)
        } else {
            Button("> Next Clip") { [self] in
                nextClip()
            }

            Button("< Previous Clip") { [self] in
                previousClip()
            }

            Button("> Next Source") { [self] in
                nextSource()
            }

            Button("< Previous Source") { [self] in
                previousSource()
            }
        }

        ForEach(0..<9, id: \.self) { [self] idx in
            Button("Select Source \(idx + 1)") {
                selectSource(index: idx)
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

        Button("New Clip") { [self] in
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

        Button("Save Hypnogram") { [self] in
            save()
        }
        .keyboardShortcut("s", modifiers: [.command])

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
        .keyboardShortcut(.delete, modifiers: [.option])
        .disabled(isTyping)

        Button("Add to Exclude List") { [self] in
            excludeCurrentSource()
        }
        .keyboardShortcut("x", modifiers: [.shift])

        Button("Add to Favorites") { [self] in
            favoriteCurrentSource()
        }
        .keyboardShortcut("f", modifiers: [.shift])

        Button("Delete") { [self] in
            markCurrentSourceForDeletion()
        }
        .keyboardShortcut(.delete, modifiers: [])
        .disabled(isTyping)

        Button("Mark for Deletion") { [self] in
            markCurrentSourceForDeletion()
        }
        .keyboardShortcut("d", modifiers: [.shift])
    }
}
