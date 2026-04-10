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
    func makeRandomComposition(preservingGlobalEffectFrom previous: Composition?) -> Composition {
        let compositionLengthMin = max(0.1, state.settings.compositionLengthMinSeconds)
        let compositionLengthMax = max(compositionLengthMin, state.settings.compositionLengthMaxSeconds)
        let compositionLengthSeconds = Double.random(in: compositionLengthMin...compositionLengthMax)
        let targetDuration = CMTime(seconds: compositionLengthSeconds, preferredTimescale: 600)
        let playRateBounds: ClosedRange<Double> = 0.2...2.0
        let configuredPlayRateMin = min(max(state.settings.compositionPlayRateMin, playRateBounds.lowerBound), playRateBounds.upperBound)
        let configuredPlayRateMax = min(max(state.settings.compositionPlayRateMax, playRateBounds.lowerBound), playRateBounds.upperBound)
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

        var compositionEffectChain = previous?.effectChain.clone()
        if shouldApplyRandomizedEffect(
            enabled: state.settings.randomGlobalEffect,
            frequency: state.settings.randomGlobalEffectFrequency
        ) {
            compositionEffectChain = randomTemplateChain() ?? compositionEffectChain
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

        var composition = Composition(
            layers: layers,
            targetDuration: targetDuration,
            playRate: selectedPlayRate,
            effectChain: compositionEffectChain,
            createdAt: Date()
        )
        composition.syncTargetDurationToLayers()
        return composition
    }

    func replaceDefaultHypnogramWithNewComposition() {
        let composition = makeRandomComposition(preservingGlobalEffectFrom: nil)
        hypnogram = makeHypnogramWithCurrentHypnogramContext(
            compositions: [composition],
            currentCompositionIndex: 0,
        )
        setActiveWorkingHypnogramURL(nil)
        clearUnsavedWorkingHypnogramChanges()
        currentCompositionIndex = 0
        player.currentLayerIndex = 0
        clearAllSaveTargets()
        applyCurrentHypnogramDocumentContextToRuntime()
        notifyHypnogramMutated()
        applyCompositionSelectionChanged(manual: false)
    }

    func replaceCurrentCompositionWithNewComposition(manual: Bool = false) {
        let replacedCompositionID = currentComposition.id
        let composition = makeRandomComposition(preservingGlobalEffectFrom: currentComposition)
        currentComposition = composition
        player.currentLayerIndex = 0
        clearSaveTarget(for: replacedCompositionID)
        pruneSaveTargetsToCurrentHypnogram()
        applyCompositionSelectionChanged(manual: manual)
    }

    func insertNewCompositionAfterCurrentAndSelect(manual: Bool) {
        persistCurrentCompositionPreviewIfNeeded()
        let composition = makeRandomComposition(preservingGlobalEffectFrom: currentComposition)
        let insertIndex = min(currentCompositionIndex + 1, hypnogram.compositions.count)
        hypnogram.compositions.insert(composition, at: insertIndex)
        currentCompositionIndex = insertIndex
        player.currentLayerIndex = 0
        pruneSaveTargetsToCurrentHypnogram()
        notifyHypnogramMutated()
        enforceDefaultHypnogramCompositionLimit()
        applyCompositionSelectionChanged(manual: manual)
    }

    @discardableResult
    func advanceOrGenerateOnCompositionEnded(loopSequenceAtEnd: Bool, generateAtEnd: Bool) -> Bool {
        persistCurrentCompositionPreviewIfNeeded()

        let nextIndex = currentCompositionIndex + 1
        if nextIndex < hypnogram.compositions.count {
            currentCompositionIndex = nextIndex
            applyCompositionSelectionChanged(manual: false)
        } else if loopSequenceAtEnd, !hypnogram.compositions.isEmpty {
            currentCompositionIndex = 0
            applyCompositionSelectionChanged(manual: false)
        } else if generateAtEnd {
            insertNewCompositionAfterCurrentAndSelect(manual: false)
        } else {
            return false
        }
        return true
    }
}
