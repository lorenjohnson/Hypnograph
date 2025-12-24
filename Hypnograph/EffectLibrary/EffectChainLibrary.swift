//
//  EffectChainLibrary.swift
//  Hypnograph
//
//  Library of available effect chains loaded from configuration.
//  Provides access to all effects and their definitions.
//  Extracted from RenderHooks.swift as part of effects architecture refactor.
//

import Foundation

/// Namespace for available effect chains
/// Effect chains are loaded from JSON config with fallback to bundled defaults
enum EffectChainLibrary {
    /// Cached loaded effect chains and source info
    private static var cachedResult: EffectConfigLoader.LoadResult?

    /// Callback triggered after effect chains are reloaded - allows managers to re-apply active effects
    static var onReload: (() -> Void)?

    /// All available effect chains (None is implicit, represented by nil)
    /// Loaded from: user config → bundled default → hardcoded fallback
    static var all: [Effect] {
        if let cached = cachedResult {
            return cached.effects
        }
        let result = EffectConfigLoader.loadEffects()
        cachedResult = result

        // Log source and notify on errors
        switch result.source {
        case .user:
            print("✓ Effect chains loaded from user config (\(result.effects.count) chains)")
        case .bundled:
            print("✓ Effect chains loaded from bundled defaults (\(result.effects.count) chains)")
        case .hardcoded:
            print("⚠️ Effect chains using hardcoded fallback")
            if result.error != nil {
                AppNotifications.show("⚠️ Effects config error - using defaults", flash: true, duration: 4.0)
            }
        }

        return result.effects
    }

    /// Update a single effect chain in the cache (used for live parameter updates)
    static func updateCachedEffect(at index: Int, with effect: Effect) {
        guard var result = cachedResult, index >= 0, index < result.effects.count else { return }
        var effects = result.effects
        effects[index] = effect
        cachedResult = EffectConfigLoader.LoadResult(effects: effects, source: result.source, error: result.error)
    }

    /// Replace the entire effect chains cache with new effects
    /// Used by EffectConfigLoader when effect chains are added/deleted in-memory
    static func updateCache(with effects: [Effect]) {
        let source = cachedResult?.source ?? .user
        cachedResult = EffectConfigLoader.LoadResult(effects: effects, source: source, error: nil)
        // Notify listeners to re-apply active effects
        onReload?()
    }

    /// Reload effect chains from config (call when config file changes)
    /// - Parameter silent: If true, don't show notification (used for live parameter updates)
    @discardableResult
    static func reload(silent: Bool = false) -> EffectConfigLoader.LoadResult {
        // Clear loader cache first so we get fresh data
        EffectConfigLoader.clearCache()

        let result = EffectConfigLoader.loadEffects()
        cachedResult = result

        // Notify user of reload result (unless silent)
        if !silent {
            switch result.source {
            case .user:
                print("✓ Effect chains reloaded from user config (\(result.effects.count) chains)")
                AppNotifications.show("Effect chains reloaded (\(result.effects.count))", flash: true, duration: 2.0)
            case .bundled:
                print("✓ Effect chains reloaded from bundled defaults")
                AppNotifications.show("Effect chains reloaded from defaults", flash: true, duration: 2.0)
            case .hardcoded:
                print("⚠️ Effect chains reload failed, using hardcoded fallback")
                AppNotifications.show("⚠️ Effects config error - using defaults", flash: true, duration: 4.0)
            }
        }

        // Notify listeners to re-apply active effect chains with new config
        onReload?()

        return result
    }

    /// Reload effect chains from a specific URL (for library switching)
    @discardableResult
    static func reload(from url: URL) -> EffectConfigLoader.LoadResult {
        do {
            let effects = try EffectConfigLoader.loadFromURL(url)
            let result = EffectConfigLoader.LoadResult(effects: effects, source: .user, error: nil)
            cachedResult = result
            print("✓ Effect chains loaded from library: \(url.lastPathComponent) (\(effects.count) chains)")

            // Notify listeners to re-apply active effect chains
            onReload?()

            return result
        } catch {
            print("⚠️ Failed to load effect chains from \(url.path): \(error)")
            // Fall back to normal reload
            return reload()
        }
    }

    /// Returns a random effect chain
    static func random() -> Effect? {
        all.randomElement()
    }
}

// MARK: - Compatibility Alias

/// Compatibility alias for HookChainLibrary -> EffectChainLibrary
typealias HookChainLibrary = EffectChainLibrary

