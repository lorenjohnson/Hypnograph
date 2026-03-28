//
//  EffectsEditorTypes.swift
//  Hypnograph
//
//  Supporting types for EffectsEditorView state and selection.
//

import Foundation
import HypnoCore

enum EffectsListSelection: Hashable {
    case current(Int)
    case recent(UUID)
    case library(UUID)
}

/// Computed selected chain from current layer's effect.
/// Reads from the recipe's stored chain (per-hypnogram), not the library.
struct SelectedChainContext {
    let chain: EffectChain
    let editableLayer: Int?
    let title: String
}
