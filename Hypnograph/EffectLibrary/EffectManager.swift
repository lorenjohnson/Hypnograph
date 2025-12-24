//
//  EffectManager.swift
//  Hypnograph
//
//  Manages effect state, frame buffer, and effect application.
//  Coordinates between the recipe (source of truth) and the rendering pipeline.
//  Extracted from RenderHooks.swift as part of effects architecture refactor.
//

import CoreGraphics
import CoreMedia
import CoreImage
import Foundation

/// Manages effect state, frame buffer, and effect application.
/// Coordinates between the recipe (source of truth) and the rendering pipeline.
final class EffectManager {

    // MARK: - Frame Buffer

    /// Shared frame buffer that persists across frames
    /// 120 frames at 30fps = 4 seconds of history for advanced datamosh/AI effects
    let frameBuffer = FrameBuffer(maxFrames: 120)

    /// Global frame counter - increments each frame, persists across video loops
    /// Used by temporal effects that need consistent timing
    private(set) var globalFrameIndex: Int = 0

    /// Increment frame counter and return current value
    func nextFrameIndex() -> Int {
        let current = globalFrameIndex
        globalFrameIndex += 1
        return current
    }

    /// Reset frame counter (call when switching montages or effects)
    func resetFrameIndex() {
        globalFrameIndex = 0
    }

    /// Create a manager for export with a frozen recipe
    /// Uses same code paths as preview but with isolated state
    static func forExport(recipe: HypnogramRecipe) -> EffectManager {
        let manager = EffectManager()
        manager.recipeProvider = { recipe }
        // No setters needed - export is read-only
        // flashSoloIndex stays nil - export renders all layers
        return manager
    }

    /// Get the maximum lookback required by any effect (global or per-source)
    var maxRequiredLookback: Int {
        guard let recipe = recipeProvider?() else { return 0 }

        // Check global effects
        let globalMax = recipe.effects.map { $0.requiredLookback }.max() ?? 0

        // Check per-source effects
        let sourceMax = recipe.sources.flatMap { $0.effects }.map { $0.requiredLookback }.max() ?? 0

        return max(globalMax, sourceMax)
    }

    // Compatibility alias for frameIndex
    var frameIndex: Int { globalFrameIndex }

    // MARK: - Recipe Integration

    /// Closure to get the current recipe (injected by RecipeManager)
    var recipeProvider: (() -> HypnogramRecipe?)?

    /// Closure to set global effects on the recipe
    var effectsSetter: (([Effect]) -> Void)?

    /// Closure to set global effect definition on the recipe
    var globalEffectDefinitionSetter: ((EffectDefinition?) -> Void)?

    /// Closure to set per-source effects on the recipe
    var sourceEffectSetter: ((Int, [Effect]) -> Void)?

    /// Closure to set per-source effect definition on the recipe
    var sourceEffectDefinitionSetter: ((Int, EffectDefinition?) -> Void)?

    /// Closure to set blend mode for a source
    var blendModeSetter: ((Int, String) -> Void)?

    /// Callback when effects change (for UI updates)
    var onEffectChanged: (() -> Void)?

    // MARK: - Flash Solo

    /// When set, only render this source index (for flash solo preview)
    var flashSoloIndex: Int?

    // MARK: - Blend Normalization

    /// Whether blend normalization is enabled (for A/B testing)
    var isNormalizationEnabled: Bool = true {
        didSet {
            if oldValue != isNormalizationEnabled {
                onEffectChanged?()
            }
        }
    }

    /// Current normalization strategy (auto-selected by default)
    private var _normalizationStrategy: NormalizationStrategy?

    /// Cached blend mode analysis (recomputed when recipe changes)
    private var cachedAnalysis: BlendModeAnalysis?

    /// Get the active normalization strategy (auto-selects if not manually set)
    /// Returns NoNormalization if normalization is disabled
    var normalizationStrategy: NormalizationStrategy {
        guard isNormalizationEnabled else {
            return NoNormalization()
        }
        if let manual = _normalizationStrategy {
            return manual
        }
        let analysis = currentBlendAnalysis
        return autoSelectNormalization(for: analysis)
    }

    /// Set a specific normalization strategy (nil = auto-select)
    func setNormalizationStrategy(_ strategy: NormalizationStrategy?) {
        _normalizationStrategy = strategy
        onEffectChanged?()
    }

    /// Get current blend mode analysis for the recipe
    var currentBlendAnalysis: BlendModeAnalysis {
        if let cached = cachedAnalysis {
            return cached
        }
        let blendModes = collectBlendModes()
        let analysis = analyzeBlendModes(blendModes)
        cachedAnalysis = analysis
        return analysis
    }

    /// Invalidate cached analysis (call when blend modes change)
    func invalidateBlendAnalysis() {
        cachedAnalysis = nil
    }

    /// Collect all blend modes from current recipe
    private func collectBlendModes() -> [String] {
        guard let recipe = recipeProvider?() else { return [] }
        return recipe.sources.enumerated().map { index, source in
            if index == 0 {
                return BlendMode.sourceOver
            }
            return source.blendMode ?? BlendMode.defaultMontage
        }
    }

    // MARK: - Init

    init() {}

    // MARK: - Context Creation

    /// Create a render context for the current frame
    func createContext(time: CMTime, outputSize: CGSize) -> RenderContext {
        RenderContext(
            frameIndex: frameIndex,
            time: time,
            outputSize: outputSize,
            frameBuffer: frameBuffer
        )
    }

    // MARK: - Global Effects (reads from recipe)

    /// Get the current global effect name
    var globalEffectName: String {
        recipeProvider?()?.effects.first?.name ?? "None"
    }

    /// Get the current global effect definition (for editing)
    var globalEffectDefinition: EffectDefinition? {
        recipeProvider?()?.effectDefinition
    }

    /// Set global effect from an Effect instance
    func setGlobalEffect(_ effect: Effect?) {
        if let effect = effect {
            effectsSetter?([effect])
        } else {
            effectsSetter?([])
        }
        onEffectChanged?()
    }

    /// Set global effect from a definition - stores definition and instantiates effect
    func setGlobalEffect(from definition: EffectDefinition?) {
        globalEffectDefinitionSetter?(definition)
        if let def = definition, let effect = EffectConfigLoader.instantiateEffect(def) {
            effectsSetter?([effect])
        } else {
            effectsSetter?([])
        }
        onEffectChanged?()
    }

    // MARK: - Hook Chain Management

    /// Update a hook's parameter in the recipe's effect chain
    /// - Parameters:
    ///   - layer: -1 for global, 0+ for source index
    ///   - hookIndex: index of the hook in the chain
    ///   - key: parameter key
    ///   - value: new parameter value
    func updateHookParameter(for layer: Int, hookIndex: Int, key: String, value: AnyCodableValue) {
        guard var definition = effectDefinition(for: layer) else { return }
        guard var hooks = definition.hooks, hookIndex >= 0, hookIndex < hooks.count else { return }

        var hook = hooks[hookIndex]
        var params = hook.params ?? [:]
        params[key] = value
        hook = EffectDefinition(name: hook.name, type: hook.type, params: params, hooks: hook.hooks)
        hooks[hookIndex] = hook
        definition = EffectDefinition(name: definition.name, type: definition.type, params: definition.params, hooks: hooks)

        setEffect(from: definition, for: layer)
    }

    /// Update a top-level effect's parameter in the recipe's effect definition
    /// - Parameters:
    ///   - layer: -1 for global, 0+ for source index
    ///   - key: parameter key
    ///   - value: new parameter value
    func updateEffectParameter(for layer: Int, key: String, value: AnyCodableValue) {
        guard var definition = effectDefinition(for: layer) else { return }

        var params = definition.params ?? [:]
        params[key] = value
        definition = EffectDefinition(name: definition.name, type: definition.type, params: params, hooks: definition.hooks)

        setEffect(from: definition, for: layer)
    }

    /// Add a hook to the recipe's effect chain for a layer
    /// - Parameters:
    ///   - layer: -1 for global, 0+ for source index
    ///   - hookType: the type of hook to add (e.g. "DatamoshMetalHook")
    func addHookToChain(for layer: Int, hookType: String) {
        guard var definition = effectDefinition(for: layer) else { return }

        var hooks = definition.hooks ?? []
        let defaults = EffectRegistry.defaults(for: hookType)
        let newHook = EffectDefinition(name: nil, type: hookType, params: defaults, hooks: nil)
        hooks.append(newHook)
        definition = EffectDefinition(name: definition.name, type: definition.type, params: definition.params, hooks: hooks)

        setEffect(from: definition, for: layer)
    }

    /// Remove a hook from the recipe's effect chain for a layer
    /// - Parameters:
    ///   - layer: -1 for global, 0+ for source index
    ///   - hookIndex: index of the hook to remove
    func removeHookFromChain(for layer: Int, hookIndex: Int) {
        guard var definition = effectDefinition(for: layer) else { return }
        guard var hooks = definition.hooks, hookIndex >= 0, hookIndex < hooks.count else { return }

        hooks.remove(at: hookIndex)
        definition = EffectDefinition(name: definition.name, type: definition.type, params: definition.params, hooks: hooks)

        setEffect(from: definition, for: layer)
    }

    /// Update the effect name in the recipe's definition
    /// - Parameters:
    ///   - layer: -1 for global, 0+ for source index
    ///   - name: new name for the effect
    func updateEffectName(for layer: Int, name: String) {
        guard var definition = effectDefinition(for: layer) else { return }

        definition = EffectDefinition(name: name, type: definition.type, params: definition.params, hooks: definition.hooks)

        setEffect(from: definition, for: layer)
    }

    /// Reorder hooks in the recipe's effect chain for a layer
    /// - Parameters:
    ///   - layer: -1 for global, 0+ for source index
    ///   - fromIndex: source index
    ///   - toIndex: destination index
    func reorderHooksInChain(for layer: Int, fromIndex: Int, toIndex: Int) {
        guard var definition = effectDefinition(for: layer) else { return }
        guard var hooks = definition.hooks else { return }
        guard fromIndex >= 0, fromIndex < hooks.count, toIndex >= 0, toIndex < hooks.count else { return }

        let hook = hooks.remove(at: fromIndex)
        hooks.insert(hook, at: toIndex)
        definition = EffectDefinition(name: definition.name, type: definition.type, params: definition.params, hooks: hooks)

        setEffect(from: definition, for: layer)
    }

    /// Reset a hook's parameters to defaults in the recipe
    /// - Parameters:
    ///   - layer: -1 for global, 0+ for source index
    ///   - hookIndex: index of the hook to reset
    func resetHookToDefaults(for layer: Int, hookIndex: Int) {
        guard var definition = effectDefinition(for: layer) else { return }
        guard var hooks = definition.hooks, hookIndex >= 0, hookIndex < hooks.count else { return }

        var hook = hooks[hookIndex]
        guard let hookType = hook.resolvedType else { return }

        // Get defaults from registry, preserve _enabled state
        var defaults = EffectRegistry.defaults(for: hookType)
        if let wasEnabled = hook.params?["_enabled"] {
            defaults["_enabled"] = wasEnabled
        }

        hook = EffectDefinition(name: hook.name, type: hook.type, params: defaults, hooks: hook.hooks)
        hooks[hookIndex] = hook
        definition = EffectDefinition(name: definition.name, type: definition.type, params: definition.params, hooks: hooks)

        setEffect(from: definition, for: layer)
    }

    func cycleGlobalEffect() {
        // Clear frame buffer and reset frame counter so new effect starts fresh
        frameBuffer.clear()
        resetFrameIndex()

        // Find current index (-1 means None)
        let currentName = globalEffectName
        let currentIndex = EffectChainLibrary.all.firstIndex { $0.name == currentName } ?? -1
        // Cycle: -1 -> 0 -> 1 -> ... -> count-1 -> -1
        let nextIndex = (currentIndex + 2) % (EffectChainLibrary.all.count + 1) - 1
        setGlobalEffect(nextIndex >= 0 ? EffectChainLibrary.all[nextIndex] : nil)
    }

    /// Re-apply active effects using fresh instances from the reloaded config.
    /// Called when effects config changes to apply parameter updates immediately.
    func reapplyActiveEffects() {
        guard let recipe = recipeProvider?() else { return }

        // Re-apply global effect by name
        if let currentEffect = recipe.effects.first {
            let currentName = currentEffect.name
            if let freshEffect = EffectChainLibrary.all.first(where: { $0.name == currentName }) {
                // Found matching effect - replace with fresh copy
                effectsSetter?([freshEffect.copy()])
                print("🔄 Reapplied global effect: \(currentName)")
            }
        }

        // Re-apply per-source effects by name
        for (index, source) in recipe.sources.enumerated() {
            if let currentEffect = source.effects.first {
                let currentName = currentEffect.name
                if let freshEffect = EffectChainLibrary.all.first(where: { $0.name == currentName }) {
                    sourceEffectSetter?(index, [freshEffect.copy()])
                    print("🔄 Reapplied source \(index) effect: \(currentName)")
                }
            }
        }

        onEffectChanged?()
    }

    // MARK: - Per-Source Effects (reads from recipe sources)

    func sourceEffectName(for sourceIndex: Int) -> String {
        guard let recipe = recipeProvider?(),
              sourceIndex >= 0,
              sourceIndex < recipe.sources.count else {
            return "None"
        }
        return recipe.sources[sourceIndex].effects.first?.name ?? "None"
    }

    func setSourceEffect(_ effect: Effect?, for sourceIndex: Int) {
        if let effect = effect {
            sourceEffectSetter?(sourceIndex, [effect])
        } else {
            sourceEffectSetter?(sourceIndex, [])
        }
        onEffectChanged?()
    }

    /// Set source effect from a definition - stores definition and instantiates hook
    func setSourceEffect(from definition: EffectDefinition?, for sourceIndex: Int) {
        sourceEffectDefinitionSetter?(sourceIndex, definition)
        if let def = definition, let hook = EffectConfigLoader.instantiateEffect(def) {
            sourceEffectSetter?(sourceIndex, [hook])
        } else {
            sourceEffectSetter?(sourceIndex, [])
        }
        onEffectChanged?()
    }

    /// Get a source's effect definition (for editing)
    func sourceEffectDefinition(for sourceIndex: Int) -> EffectDefinition? {
        guard let recipe = recipeProvider?(),
              sourceIndex >= 0,
              sourceIndex < recipe.sources.count else {
            return nil
        }
        return recipe.sources[sourceIndex].effectDefinition
    }

    func cycleSourceEffect(for sourceIndex: Int) {
        let currentName = sourceEffectName(for: sourceIndex)
        let currentIndex = EffectChainLibrary.all.firstIndex { $0.name == currentName } ?? -1
        let nextIndex = (currentIndex + 2) % (EffectChainLibrary.all.count + 1) - 1
        setSourceEffect(nextIndex >= 0 ? EffectChainLibrary.all[nextIndex] : nil, for: sourceIndex)
    }

    // MARK: - Unified Layer API (layer -1 = global, 0+ = source)

    /// Get effect name for a layer (-1 = global, 0+ = source index)
    func effectName(for layer: Int) -> String {
        if layer == -1 {
            return globalEffectName
        }
        return sourceEffectName(for: layer)
    }

    /// Get effect definition for a layer (-1 = global, 0+ = source index)
    func effectDefinition(for layer: Int) -> EffectDefinition? {
        if layer == -1 {
            return globalEffectDefinition
        }
        return sourceEffectDefinition(for: layer)
    }

    /// Set effect for a layer (-1 = global, 0+ = source index)
    func setEffect(_ effect: Effect?, for layer: Int) {
        if layer == -1 {
            setGlobalEffect(effect)
        } else {
            setSourceEffect(effect, for: layer)
        }
    }

    /// Set effect from a definition for a layer (-1 = global, 0+ = source index)
    /// This is the preferred method for selecting effects from the library
    func setEffect(from definition: EffectDefinition?, for layer: Int) {
        if layer == -1 {
            setGlobalEffect(from: definition)
        } else {
            setSourceEffect(from: definition, for: layer)
        }
    }

    /// Cycle effect for a layer (-1 = global, 0+ = source index)
    /// direction: 1 = forward, -1 = backward
    func cycleEffect(for layer: Int, direction: Int = 1) {
        // Clear frame buffer and reset frame counter so new effect starts fresh
        frameBuffer.clear()
        resetFrameIndex()

        let currentName = effectName(for: layer)
        let currentIndex = EffectChainLibrary.all.firstIndex { $0.name == currentName } ?? -1

        // Cycle through effects: -1 (None) -> 0 -> 1 -> ... -> count-1 -> -1
        let effectCount = EffectChainLibrary.all.count
        let totalStates = effectCount + 1  // +1 for "None"

        // Convert to 0-based index where 0 = None, 1+ = effects
        let current0Based = currentIndex + 1
        let next0Based = (current0Based + direction + totalStates) % totalStates
        let nextIndex = next0Based - 1  // Back to -1 based

        setEffect(nextIndex >= 0 ? EffectChainLibrary.all[nextIndex] : nil, for: layer)
    }

    /// Clear effect for a specific layer (-1 = global, 0+ = source index)
    func clearEffect(for layer: Int) {
        setEffect(nil, for: layer)
    }

    // MARK: - Application

    /// Apply recipe effects to the final composed image
    func applyGlobal(to context: inout RenderContext, image: CIImage) -> CIImage {
        // Global effect is not tied to a particular source.
        context.sourceIndex = nil

        // Skip global effects during flash solo - show raw source
        if flashSoloIndex != nil {
            frameBuffer.addFrame(image, at: context.time)
            return image
        }

        guard let recipe = recipeProvider?(), !recipe.effects.isEmpty else {
            // Even if no effect, still update buffer for future use
            frameBuffer.addFrame(image, at: context.time)
            return image
        }

        // Apply all effects in chain (currently UI only sets one)
        var result = image
        for effect in recipe.effects {
            result = effect.willRenderFrame(&context, image: result)
        }

        // Update frame buffer with processed result so temporal effects see prior effects
        frameBuffer.addFrame(result, at: context.time)

        return result
    }

    /// Apply per-source effects to a single source image (before compositing)
    func applyToSource(sourceIndex: Int, context: inout RenderContext, image: CIImage) -> CIImage {
        guard let recipe = recipeProvider?(),
              sourceIndex >= 0,
              sourceIndex < recipe.sources.count else {
            return image
        }

        let effects = recipe.sources[sourceIndex].effects
        guard !effects.isEmpty else { return image }

        // Mark which source is being processed so hooks can branch if they want.
        context.sourceIndex = sourceIndex

        var result = image
        for effect in effects {
            result = effect.willRenderFrame(&context, image: result)
        }
        return result
    }

    func clearFrameBuffer() {
        print("🔄 EffectManager: clearFrameBuffer() - clearing \(frameBuffer.frameCount) frames")
        frameBuffer.clear()
        resetFrameIndex()

        // Reset all effects that have internal state (HoldFrameEffect, DatamoshEffect, etc.)
        // Important: Do this BEFORE the recipe clears effects, because effects may be preserved
        if let recipe = recipeProvider?() {
            for effect in recipe.effects {
                effect.reset()
            }
            for source in recipe.sources {
                for effect in source.effects {
                    effect.reset()
                }
            }
        }
    }

    // MARK: - Blend Modes (reads from recipe sources)

    func blendMode(for sourceIndex: Int) -> String {
        // Source 0 is always source-over (base layer)
        if sourceIndex == 0 {
            return BlendMode.sourceOver
        }
        // Read from the recipe (single source of truth)
        guard let recipe = recipeProvider?(),
              sourceIndex >= 0,
              sourceIndex < recipe.sources.count else {
            return BlendMode.defaultMontage
        }
        return recipe.sources[sourceIndex].blendMode ?? BlendMode.defaultMontage
    }

    func setBlendMode(_ mode: String, for sourceIndex: Int, silent: Bool = false) {
        blendModeSetter?(sourceIndex, mode)
        invalidateBlendAnalysis()  // Blend modes changed, recalculate analysis
        if !silent {
            onEffectChanged?()
        }
    }

    func cycleBlendMode(for sourceIndex: Int) {
        // Don't cycle source 0 - it's always source-over
        guard sourceIndex > 0 else { return }

        let currentMode = blendMode(for: sourceIndex)
        let currentIndex = BlendMode.all.firstIndex(of: currentMode) ?? 0
        let nextIndex = (currentIndex + 1) % BlendMode.all.count
        setBlendMode(BlendMode.all[nextIndex], for: sourceIndex)
    }

    // MARK: - Blend Normalization Helpers

    /// Get compensated opacity for a layer (for use during compositing)
    func compensatedOpacity(
        layerIndex: Int,
        totalLayers: Int,
        blendMode: String
    ) -> CGFloat {
        let analysis = currentBlendAnalysis
        return normalizationStrategy.opacityForLayer(
            index: layerIndex,
            totalLayers: totalLayers,
            blendMode: blendMode,
            analysis: analysis
        )
    }

    /// Apply post-composition normalization (call after all layers blended, before global effects)
    func applyNormalization(to image: CIImage) -> CIImage {
        let analysis = currentBlendAnalysis
        return normalizationStrategy.normalizeComposite(image, analysis: analysis)
    }

    // MARK: - Flash Solo

    /// Set flash solo to show only the specified source index
    func setFlashSolo(_ sourceIndex: Int?) {
        // Only trigger effect change if the value actually changed
        guard flashSoloIndex != sourceIndex else { return }
        flashSoloIndex = sourceIndex
        onEffectChanged?()
    }

    /// Check if a given source should be visible (respects flash solo)
    func shouldRenderSource(at sourceIndex: Int) -> Bool {
        guard let soloIndex = flashSoloIndex else {
            return true  // No flash solo active, render all
        }
        return sourceIndex == soloIndex
    }
}

/// Compatibility alias for RenderHookManager -> EffectManager
typealias RenderHookManager = EffectManager
