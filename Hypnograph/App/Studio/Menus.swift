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
    func playbackMenu() -> some View {
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
                    toggleLoopCompositionMode()
                } else if isLoopCompositionEnabled {
                    setPlaybackLoopMode(.off)
                }
            }
        ))
        .keyboardShortcut("l", modifiers: [])
        .disabled(disableMainWindowShortcuts)

        Toggle("Loop Sequence", isOn: Binding(
            get: { [self] in isLoopSequenceEnabled },
            set: { [self] in
                setPlaybackLoopMode($0 ? .sequence : .off)
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
        .disabled(disableMainWindowShortcuts)

        // Aspect Ratio
        Section("Aspect Ratio") {
            ForEach(AspectRatio.menuPresets, id: \.displayString) { ratio in
                Toggle(ratio.menuLabel, isOn: Binding(
                    get: { [self] in currentHypnogramAspectRatio == ratio },
                    set: { [self] in if $0 { setAspectRatio(ratio) } }
                ))
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
        Button("Save as Favorite") { [self] in
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

        Section("Add Layer") {
            Button("From Files...") { [self] in
                addSourceFromFilesPanel()
            }

            Button("From Photos...") { [self] in
                addSourceFromPhotosPicker()
            }
            .disabled(!state.photosAuthorizationStatus.canRead)

            Button("Random Source") { [self] in
                addSourceFromRandom()
            }
            .keyboardShortcut("n", modifiers: [.shift])
            .disabled(disableMainWindowShortcuts)
        }

        Divider()

        Section("Effects") {
            Button("Next") { [self] in
                cycleEffect(direction: 1)
            }
            .keyboardShortcut("e", modifiers: [.command])

            Button("Previous") { [self] in
                cycleEffect(direction: -1)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Clear") { [self] in
                activeEffectManager.clearEffect(for: -1)
            }

            Button("Clear for All Layers") { [self] in
                clearAllEffects()
            }
            .keyboardShortcut("c", modifiers: [.control, .shift])
            .disabled(disableMainWindowShortcuts)
        }
    }

    @ViewBuilder
    func sourceMenu() -> some View {
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
                selectCompositionLayer()
            }
            .keyboardShortcut("`", modifiers: [])
            .disabled(disableMainWindowShortcuts)

            ForEach(0..<9, id: \.self) { [self] idx in
                Button("Select \(idx + 1)") { [self] in
                    self.selectSource(idx)
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
