//
//  EffectsActions.swift
//  Hypnograph
//

import Foundation
import HypnoCore

@MainActor
extension Studio {
    func clearAllEffects() {
        activeEffectManager.clearEffect(for: -1)

        let sourceCount = isLiveMode
            ? livePlayer.activeLayerCount
            : currentLayers.count

        for i in 0..<sourceCount {
            activeEffectManager.clearEffect(for: i)
            if !isLiveMode && i > 0 && i < currentLayers.count {
                currentLayers[i].blendMode = BlendMode.defaultMontage
            }
        }
    }
}
