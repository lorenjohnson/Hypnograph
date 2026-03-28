//
//  GenerationActions.swift
//  Hypnograph
//

import Foundation
import CoreMedia
import HypnoCore
import HypnoUI

@MainActor
extension Studio {
    private func makeRandomComposition(preservingGlobalEffectFrom previous: Composition?) -> Composition {
        let clipLengthMin = max(0.1, state.settings.clipLengthMinSeconds)
        let clipLengthMax = max(clipLengthMin, state.settings.clipLengthMaxSeconds)
        let clipLengthSeconds = Double.random(in: clipLengthMin...clipLengthMax)
        let targetDuration = CMTime(seconds: clipLengthSeconds, preferredTimescale: 600)
        let playRateBounds: ClosedRange<Double> = 0.2...2.0
        let configuredPlayRateMin = min(max(state.settings.clipPlayRateMin, playRateBounds.lowerBound), playRateBounds.upperBound)
        let configuredPlayRateMax = min(max(state.settings.clipPlayRateMax, playRateBounds.lowerBound), playRateBounds.upperBound)
        let playRateMin = min(configuredPlayRateMin, configuredPlayRateMax)
        let playRateMax = max(configuredPlayRateMin, configuredPlayRateMax)
        let selectedPlayRate: Float = {
            guard playRateMax > playRateMin else { return Float(playRateMin) }
            let randomRate = Double.random(in: playRateMin...playRateMax)
            let steppedRate = (randomRate * 10).rounded() / 10
            return Float(min(max(steppedRate, playRateBounds.lowerBound), playRateBounds.upperBound))
        }()

        let maxLayers = max(1, player.config.maxLayers)
        let layerCount = Int.random(in: 1...maxLayers)
        let randomTemplates = effectsLibrarySession.chains.filter { $0.hasEnabledEffects }

        func shouldApplyRandomizedEffect(enabled: Bool, frequency: Double) -> Bool {
            guard enabled else { return false }
            let chance = min(max(frequency, 0), 1)
            guard chance > 0 else { return false }
            return Double.random(in: 0...1) < chance
        }

        func randomTemplateChain() -> EffectChain? {
            guard let template = randomTemplates.randomElement() else { return nil }
            return EffectChain(duplicating: template, sourceTemplateId: template.id)
        }

        var globalEffectChain = previous?.effectChain.clone()
        if shouldApplyRandomizedEffect(
            enabled: state.settings.randomGlobalEffect,
            frequency: state.settings.randomGlobalEffectFrequency
        ) {
            globalEffectChain = randomTemplateChain() ?? globalEffectChain
        }

        var layers: [Layer] = []
        layers.reserveCapacity(layerCount)

        for i in 0..<layerCount {
            guard let mediaClip = state.library.randomClip(clipLength: targetDuration.seconds) else { continue }
            let blendMode = (i == 0) ? BlendMode.sourceOver : BlendMode.defaultMontage
            let layerEffectChain: EffectChain
            if shouldApplyRandomizedEffect(
                enabled: state.settings.randomLayerEffect,
                frequency: state.settings.randomLayerEffectFrequency
            ) {
                layerEffectChain = randomTemplateChain() ?? EffectChain()
            } else {
                layerEffectChain = EffectChain()
            }

            layers.append(
                Layer(
                    mediaClip: mediaClip,
                    blendMode: blendMode,
                    effectChain: layerEffectChain
                )
            )
        }

        return Composition(
            layers: layers,
            targetDuration: targetDuration,
            playRate: selectedPlayRate,
            effectChain: globalEffectChain,
            createdAt: Date()
        )
    }

    func replaceHistoryWithNewClip() {
        let composition = makeRandomComposition(preservingGlobalEffectFrom: nil)
        player.hypnogram = Hypnogram(compositions: [composition])
        player.currentCompositionIndex = 0
        player.currentLayerIndex = -1
        player.notifyHypnogramMutated()
        applyClipSelectionChanged(manual: false)
    }

    func replaceCurrentClipWithNewClip(manual: Bool = false) {
        let composition = makeRandomComposition(preservingGlobalEffectFrom: player.currentComposition)
        player.currentComposition = composition
        player.currentLayerIndex = -1
        applyClipSelectionChanged(manual: manual)
    }

    func appendNewClipAndSelect(manual: Bool) {
        let composition = makeRandomComposition(preservingGlobalEffectFrom: player.currentComposition)
        player.hypnogram.compositions.append(composition)
        player.currentCompositionIndex = player.hypnogram.compositions.count - 1
        player.currentLayerIndex = -1
        player.notifyHypnogramMutated()
        enforceHistoryLimit()
        applyClipSelectionChanged(manual: manual)
    }

    @discardableResult
    func advanceOrGenerateOnClipEnded() -> Bool {
        guard state.settings.playbackEndBehavior == .autoAdvance else { return false }

        if timelinePlaybackDirection < 0 {
            let previousIndex = player.currentCompositionIndex - 1
            guard previousIndex >= 0 else { return false }
            player.currentCompositionIndex = previousIndex
            applyClipSelectionChanged(manual: false)
            return true
        }

        let nextIndex = player.currentCompositionIndex + 1
        if nextIndex < player.hypnogram.compositions.count {
            player.currentCompositionIndex = nextIndex
            applyClipSelectionChanged(manual: false)
        } else {
            appendNewClipAndSelect(manual: false)
        }
        return true
    }
}
