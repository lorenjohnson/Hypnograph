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
        let modeLabel = (mode == .montage ? "Montage" : "Sequence")
        items.append(.text("Dream: \(modeLabel)", order: 11, font: .subheadline))
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
            switch mode {
            case .montage:
                items.append(.text("Blend mode (M): \(currentBlendModeDisplayName())", order: 26))
            case .sequence:
                let totalSecs = sequenceTotalDuration().seconds
                items.append(.text(String(format: "Duration: %.1fs", totalSecs), order: 26))
                if let clip = activePlayer.currentClip {
                    items.append(.text("Clip: \(String(format: "%.1fs", clip.duration.seconds))", order: 27))
                }
            }

        }

        items.append(.padding(16, order: 39))

        // Keyboard hints
        items.append(.text("Shortcuts", order: 40, font: .subheadline))
        items.append(.text(". = New clip | M = Blend | Delete = Remove source", order: 41))
        items.append(.text("Cmd+E = Cycle effect | C = Clear layer | Ctrl+Shift+C = Clear all", order: 42))
        items.append(.text("E = Effects editor | 0 = Global | 1-9 = Source", order: 43))
        items.append(.text("Left/Right = Navigate | N = New | Shift+N = Add source", order: 44))
        items.append(.text("Cmd+S = Save | Cmd+F = Favorite hypnogram", order: 45))
        items.append(.text("` = Cycle Montage/Sequence/Live | Shift+X/D = Exclude/Mark delete", order: 46))

        return items
    }

    // MARK: - Menus

    /// Whether a text field is being edited - disables single-key shortcuts
    fileprivate var isTyping: Bool { state.isTyping }

    @ViewBuilder
    func compositionMenu() -> some View {
        Button("Cycle Mode (Montage/Sequence/Live)") { [self] in
            cycleMode()
        }
        .keyboardShortcut("`", modifiers: [])
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
            Button("> Next Source") { [self] in
                nextSource()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(isTyping)

            Button("< Previous Source") { [self] in
                previousSource()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(isTyping)
        } else {
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
        .keyboardShortcut("0", modifiers: [])
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

        Button("New Hypnogram") { [self] in
            new()
        }
        .keyboardShortcut("n", modifiers: [])
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

        Divider()

        Button("New Random Clip") { [self] in
            newRandomClip()
        }
        .keyboardShortcut(".", modifiers: [])
        .disabled(isTyping)

        Divider()

        Button("Delete") { [self] in
            deleteCurrentSource()
        }
        .keyboardShortcut(.delete, modifiers: [])
        .disabled(isTyping)

        Button("Add to Exclude List") { [self] in
            excludeCurrentSource()
        }
        .keyboardShortcut("x", modifiers: [.shift])

        Button("Mark for Deletion") { [self] in
            markCurrentSourceForDeletion()
        }
        .keyboardShortcut("d", modifiers: [.shift])
    }
}
