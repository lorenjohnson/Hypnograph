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
        activePlayer.currentLayerIndex >= 0 && activePlayer.currentLayerIndex < currentLayers.count
    }

    @ViewBuilder
    func playerMenu() -> some View {
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

        Toggle("Loop Composition", isOn: Binding(
            get: { [self] in isLoopCompositionEnabled },
            set: { [self] in
                if $0 {
                    toggleCompositionLoopMode()
                } else if isLoopCompositionEnabled {
                    setLoopMode(.off)
                }
            }
        ))
        .keyboardShortcut("l", modifiers: [])
        .disabled(disableMainWindowShortcuts)

        Toggle("Loop Sequence", isOn: Binding(
            get: { [self] in isLoopSequenceEnabled },
            set: { [self] in
                setLoopMode($0 ? .sequence : .off)
            }
        ))
        .keyboardShortcut("l", modifiers: [.shift])
        .disabled(disableMainWindowShortcuts)

        Divider()

        Toggle("Generate at End", isOn: Binding(
            get: { [self] in isGenerateAtEndEnabled },
            set: { [self] in
                if $0 != isGenerateAtEndEnabled {
                    toggleGenerateAtEnd()
                }
            }
        ))
        .keyboardShortcut("g", modifiers: [])
        .disabled(disableMainWindowShortcuts)

        // Aspect Ratio
        Section("Aspect Ratio") {
            ForEach(AspectRatio.menuPresets, id: \.displayString) { ratio in
                Toggle(isOn: Binding(
                    get: { [self] in currentHypnogramAspectRatio == ratio },
                    set: { [self] in if $0 { setAspectRatio(ratio) } }
                )) {
                    Label(ratio.menuLabel, systemImage: self.aspectRatioSystemImage(for: ratio))
                }
            }
        }
        .id("aspect-ratio-\(currentHypnogramAspectRatio.displayString)")

        // Output Resolution
        Section("Output Resolution") {
            ForEach(OutputResolution.allCases, id: \.self) { resolution in
                Toggle(resolution.displayName, isOn: Binding(
                    get: { [self] in currentHypnogramOutputResolution == resolution },
                    set: { [self] in if $0 { setOutputResolution(resolution) } }
                ))
            }
        }
        .id("output-resolution-\(currentHypnogramOutputResolution.rawValue)")
    }

    @ViewBuilder
    func compositionMenu() -> some View {
        Button("Favorite") { [self] in
            favoriteCurrentHypnogram()
        }
        .keyboardShortcut("f", modifiers: [.command])
        .disabled(disableMainWindowShortcuts)

        Button("Delete") { [self] in
            deleteCurrentComposition()
        }
        .keyboardShortcut(.delete, modifiers: [.command])
        .disabled(disableMainWindowShortcuts)

        Divider()

        Section("Effect Chain") {
            Button("Next") { [self] in
                cycleCompositionEffect(direction: 1)
            }
            .keyboardShortcut("e", modifiers: [])

            Button("Previous") { [self] in
                cycleCompositionEffect(direction: -1)
            }
            .keyboardShortcut("e", modifiers: [.shift])

            Button("Clear") { [self] in
                clearCompositionEffect()
            }
            .keyboardShortcut("c", modifiers: [])
        }
    }

    @ViewBuilder
    func sourceMenu() -> some View {
        Button("Add from Files...") { [self] in
            addSourceFromFilesPanel()
        }

        Button("Add from Photos...") { [self] in
            addSourceFromPhotosPicker()
        }
        .disabled(!state.photosAuthorizationStatus.canRead)

        Button("Add Random Source") { [self] in
            addSourceFromRandom()
        }
        .keyboardShortcut("n", modifiers: [.shift])
        .disabled(disableMainWindowShortcuts)

        Divider()

        Button("Cycle Blend Mode") { [self] in
            cycleBlendMode()
        }
        .keyboardShortcut("m", modifiers: [])
        .disabled(disableMainWindowShortcuts || !hasSelectedActualLayer)

        Button("Delete") { [self] in
            removeCurrentLayer()
        }
        .keyboardShortcut(.delete, modifiers: [])
        .disabled(disableMainWindowShortcuts || !hasSelectedActualLayer)

        Divider()

        Section("Effect Chain") {
            Button("Clear") { [self] in
                clearCurrentLayerEffect()
            }
            .keyboardShortcut("c", modifiers: [.shift])
            .disabled(disableMainWindowShortcuts || !hasSelectedActualLayer)

            Button("Clear for All Layers") { [self] in
                clearAllLayerEffects()
            }
            .disabled(disableMainWindowShortcuts)

            Button("Next") { [self] in
                cycleCurrentLayerEffect(direction: 1)
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(disableMainWindowShortcuts || !hasSelectedActualLayer)

            Button("Previous") { [self] in
                cycleCurrentLayerEffect(direction: -1)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(disableMainWindowShortcuts || !hasSelectedActualLayer)
        }

        Section("Source") {
            Button("New Random") { [self] in
                randomizeCurrentSource()
            }
            .keyboardShortcut(".", modifiers: [])
            .disabled(disableMainWindowShortcuts || !hasSelectedActualLayer)

            Button("Favorite") { [self] in
                favoriteCurrentSource()
            }
            .keyboardShortcut("f", modifiers: [.shift])
            .disabled(disableMainWindowShortcuts || !hasSelectedActualLayer)

            Button("Exclude") { [self] in
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

            Menu("Current") {
                currentSelectionMenuItem(title: "Layer 1", index: 0, shortcut: "1")
                currentSelectionMenuItem(title: "Layer 2", index: 1, shortcut: "2")
                currentSelectionMenuItem(title: "Layer 3", index: 2, shortcut: "3")
                currentSelectionMenuItem(title: "Layer 4", index: 3, shortcut: "4")
                currentSelectionMenuItem(title: "Layer 5", index: 4, shortcut: "5")
                currentSelectionMenuItem(title: "Layer 6", index: 5, shortcut: "6")
                currentSelectionMenuItem(title: "Layer 7", index: 6, shortcut: "7")
                currentSelectionMenuItem(title: "Layer 8", index: 7, shortcut: "8")
                currentSelectionMenuItem(title: "Layer 9", index: 8, shortcut: "9")
            }
        }
    }

    @ViewBuilder
    private func currentSelectionMenuItem(title: String, index: Int, shortcut: KeyEquivalent) -> some View {
        Button {
            self.selectSource(index)
        } label: {
            if activePlayer.currentLayerIndex == index {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .keyboardShortcut(shortcut, modifiers: [])
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

    private func aspectRatioSystemImage(for ratio: AspectRatio) -> String {
        switch ratio.displayString {
        case "fill":
            return "aspectratio"
        case "16:9":
            return "rectangle.ratio.16.to.9"
        case "9:16":
            return "rectangle.portrait"
        case "4:3":
            return "rectangle.ratio.4.to.3"
        case "1:1":
            return "square"
        default:
            return "aspectratio"
        }
    }
}
