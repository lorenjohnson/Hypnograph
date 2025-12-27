//
//  EffectConfigLoader.swift
//  Hypnograph
//
//  Loads and parses effect configuration from JSON files.
//  Supports JSONC (JSON with comments) via pre-parse stripping.
//

import Foundation
import CryptoKit

/// Loads effect configurations from JSON files
enum EffectConfigLoader {

    // MARK: - Cached State (for Effects Editor)

    /// Cached library configuration
    private static var cachedConfig: EffectLibraryConfig?
    private static var cachedConfigURL: URL?

    /// Current effect chain presets (for library UI)
    static var currentChains: [EffectChain] {
        if let config = cachedConfig {
            return config.effects
        }
        // Load and cache
        _ = loadChainsWithDefinitions()
        return cachedConfig?.effects ?? []
    }

    /// @deprecated Use currentChains instead
    static var currentDefinitions: [EffectChain] { currentChains }

    /// Callback for live effect chain updates (set by HypnographState)
    static var onEffectChainUpdated: ((Int, EffectChain) -> Void)?

    /// Debounce timer for async file save AND effect instantiation
    private static var saveTimer: Timer?
    private static let saveDebounceInterval: TimeInterval = 0.3

    /// Track which effects need re-instantiation
    private static var pendingInstantiations: Set<Int> = []

    // MARK: - Dirty Tracking (Hash-based)

    /// Hash of the last saved/loaded config - used to detect unsaved changes
    private static var savedConfigHash: String?

    /// Callback when autosave setting is needed (injected by app)
    static var isAutosaveEnabled: (() -> Bool)?

    /// Whether there are unsaved changes (compares current config hash to saved hash)
    static var hasUnsavedChanges: Bool {
        guard let config = cachedConfig else { return false }
        guard let savedHash = savedConfigHash else { return true }
        return computeConfigHash(config) != savedHash
    }

    /// Compute SHA-256 hash of a config for dirty comparison
    private static func computeConfigHash(_ config: EffectLibraryConfig) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]  // Ensure consistent ordering
        guard let data = try? encoder.encode(config) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Update saved hash to match current config (call after save or load)
    private static func updateSavedHash() {
        guard let config = cachedConfig else {
            savedConfigHash = nil
            return
        }
        savedConfigHash = computeConfigHash(config)
    }

    /// Update an effect's parameter value - updates cache immediately, defers instantiation and save
    static func updateParameter(effectIndex: Int, effectDefIndex: Int?, paramName: String, value: AnyCodableValue) {
        guard var config = cachedConfig else { return }
        guard effectIndex >= 0 && effectIndex < config.effects.count else { return }

        var chain = config.effects[effectIndex]

        if let defIdx = effectDefIndex {
            // Update an effect definition's parameter
            guard defIdx >= 0 && defIdx < chain.effects.count else { return }
            var params = chain.effects[defIdx].params ?? [:]
            params[paramName] = value
            chain.effects[defIdx].params = params
        } else {
            // Update the chain's own parameter (future: chain-level params)
            var params = chain.params ?? [:]
            params[paramName] = value
            chain.params = params
        }

        var effects = config.effects
        effects[effectIndex] = chain
        config = EffectLibraryConfig(version: config.version, effects: effects)
        cachedConfig = config

        // Schedule debounced instantiation and save
        scheduleInstantiationAndSave(effectIndex: effectIndex)
    }

    /// Add an effect to an effect chain
    static func addEffectToChain(effectIndex: Int, effectType: String) {
        guard var config = cachedConfig else { return }
        guard effectIndex >= 0 && effectIndex < config.effects.count else { return }

        var chain = config.effects[effectIndex]

        // Create new effect with default params from registry
        let defaultParams = EffectRegistry.defaults(for: effectType)
        let newEffect = EffectDefinition(type: effectType, params: defaultParams)
        chain.effects.append(newEffect)

        var effects = config.effects
        effects[effectIndex] = chain
        config = EffectLibraryConfig(version: config.version, effects: effects)
        cachedConfig = config

        scheduleInstantiationAndSave(effectIndex: effectIndex)
    }

    /// Remove an effect from an effect chain
    static func removeEffectFromChain(effectIndex: Int, effectDefIndex: Int) {
        guard var config = cachedConfig else { return }
        guard effectIndex >= 0 && effectIndex < config.effects.count else { return }

        var chain = config.effects[effectIndex]
        guard effectDefIndex >= 0 && effectDefIndex < chain.effects.count else { return }

        chain.effects.remove(at: effectDefIndex)

        var effects = config.effects
        effects[effectIndex] = chain
        config = EffectLibraryConfig(version: config.version, effects: effects)
        cachedConfig = config

        scheduleInstantiationAndSave(effectIndex: effectIndex)
    }

    /// Create a new effect chain with BasicEffect as default
    /// Returns the index of the new chain
    @discardableResult
    static func createNewEffect() -> Int {
        var config = cachedConfig ?? EffectLibraryConfig(version: 1, effects: [])

        // Generate unique name
        let baseName = "Effect"
        let existingNames = Set(config.effects.compactMap { $0.name })
        var uniqueName = baseName
        var counter = 1
        while existingNames.contains(uniqueName) {
            counter += 1
            uniqueName = "\(baseName) \(counter)"
        }

        // Create chain with BasicEffect as default effect
        let basicDefaults = EffectRegistry.defaults(for: "BasicEffect")
        let basicEffect = EffectDefinition(type: "BasicEffect", params: basicDefaults)
        let newChain = EffectChain(name: uniqueName, effects: [basicEffect])

        var effects = config.effects
        effects.append(newChain)
        config = EffectLibraryConfig(version: config.version, effects: effects)
        cachedConfig = config

        // Reload EffectChainLibrary.all to include the new chain
        reloadEffectAll()

        scheduleSave()
        return effects.count - 1
    }

    /// Delete an effect chain at the given index
    static func deleteEffect(at index: Int) {
        guard var config = cachedConfig else { return }
        guard index >= 0 && index < config.effects.count else { return }

        var effects = config.effects
        effects.remove(at: index)
        config = EffectLibraryConfig(version: config.version, effects: effects)
        cachedConfig = config

        // Reload EffectChainLibrary.all to reflect the deletion
        reloadEffectAll()

        scheduleSave()
    }

    /// Reload EffectChainLibrary.all from cached config
    /// This directly updates EffectChainLibrary's cache without clearing our in-memory config
    private static func reloadEffectAll() {
        guard let config = cachedConfig else { return }

        // Directly update EffectChainLibrary's cached result without going through reload()
        // which would clear our in-memory config
        EffectChainLibrary.updateCache(with: config.effects)
    }

    /// Reorder effects in an effect chain
    static func reorderEffectsInChain(effectIndex: Int, fromIndex: Int, toIndex: Int) {
        guard var config = cachedConfig else { return }
        guard effectIndex >= 0 && effectIndex < config.effects.count else { return }

        var chain = config.effects[effectIndex]
        guard fromIndex >= 0 && fromIndex < chain.effects.count else { return }
        guard toIndex >= 0 && toIndex < chain.effects.count else { return }

        let effect = chain.effects.remove(at: fromIndex)
        chain.effects.insert(effect, at: toIndex)

        var effects = config.effects
        effects[effectIndex] = chain
        config = EffectLibraryConfig(version: config.version, effects: effects)
        cachedConfig = config

        scheduleInstantiationAndSave(effectIndex: effectIndex)
    }

    /// Toggle effect enabled state (stored as _enabled param)
    static func setEffectEnabled(effectIndex: Int, effectDefIndex: Int, enabled: Bool) {
        updateParameter(effectIndex: effectIndex, effectDefIndex: effectDefIndex, paramName: "_enabled", value: .bool(enabled))
    }

    /// Reset an effect's parameters to their default values
    static func resetEffectToDefaults(effectIndex: Int, effectDefIndex: Int) {
        guard var config = cachedConfig else { return }
        guard effectIndex >= 0 && effectIndex < config.effects.count else { return }

        var chain = config.effects[effectIndex]
        guard effectDefIndex >= 0 && effectDefIndex < chain.effects.count else { return }

        let effectDef = chain.effects[effectDefIndex]

        // Get defaults, preserve _enabled state
        var defaults = EffectRegistry.defaults(for: effectDef.type)
        if let wasEnabled = effectDef.params?["_enabled"] {
            defaults["_enabled"] = wasEnabled
        }

        chain.effects[effectDefIndex].params = defaults

        var effects = config.effects
        effects[effectIndex] = chain
        config = EffectLibraryConfig(version: config.version, effects: effects)
        cachedConfig = config

        scheduleInstantiationAndSave(effectIndex: effectIndex)
    }

    /// Update the name of an effect chain
    static func updateEffectName(effectIndex: Int, name: String) {
        guard var config = cachedConfig else { return }
        guard effectIndex >= 0 && effectIndex < config.effects.count else { return }

        var chain = config.effects[effectIndex]
        chain.name = name

        var effects = config.effects
        effects[effectIndex] = chain
        config = EffectLibraryConfig(version: config.version, effects: effects)
        cachedConfig = config

        scheduleInstantiationAndSave(effectIndex: effectIndex)
    }

    /// Schedule debounced instantiation AND file save
    /// Batches multiple rapid changes into a single heavy operation
    private static func scheduleInstantiationAndSave(effectIndex: Int) {
        // Track which chains need re-instantiation
        pendingInstantiations.insert(effectIndex)

        // Cancel any pending timer
        saveTimer?.invalidate()

        // Schedule combined instantiation + conditional save after debounce interval
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceInterval, repeats: false) { _ in
            performPendingInstantiations()
            // Only save to file if autosave is enabled
            if isAutosaveEnabled?() ?? true {
                save()
            }
        }
    }

    /// Perform all pending chain updates in one batch
    private static func performPendingInstantiations() {
        guard let config = cachedConfig else {
            pendingInstantiations.removeAll()
            return
        }

        for effectIndex in pendingInstantiations {
            guard effectIndex >= 0 && effectIndex < config.effects.count else { continue }
            let chain = config.effects[effectIndex]
            onEffectChainUpdated?(effectIndex, chain)
        }
        pendingInstantiations.removeAll()
    }

    /// Schedule a debounced save to file (for operations that don't need re-instantiation)
    private static func scheduleSave() {
        // Cancel any pending save
        saveTimer?.invalidate()

        // Schedule new save after debounce interval (only if autosave enabled)
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceInterval, repeats: false) { _ in
            if isAutosaveEnabled?() ?? true {
                save()
            }
        }
    }

    /// Save current config to file
    /// - Parameter url: Optional URL to save to. If nil, saves to default userConfigURL
    /// - Note: Only marks clean when saving to the default location
    static func save(to url: URL? = nil) {
        guard let config = cachedConfig else { return }
        let targetURL = url ?? userConfigURL
        let isDefaultLocation = (url == nil)

        // Save on background queue
        DispatchQueue.global(qos: .utility).async {
            do {
                // Ensure directory exists
                let directory = targetURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(config)
                try data.write(to: targetURL)
                print("✓ Effects saved to \(targetURL.path)")

                // Update saved hash when saving to the default location
                if isDefaultLocation {
                    DispatchQueue.main.async {
                        updateSavedHash()
                    }
                }
            } catch {
                print("⚠️ EffectConfigLoader: Failed to save config: \(error)")
            }
        }
    }

    // MARK: - File Locations

    /// User's custom config location
    static var userConfigURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let hypnographDir = appSupport.appendingPathComponent("Hypnograph", isDirectory: true)
        return hypnographDir.appendingPathComponent("effects.json")
    }
    
    /// Bundled default config
    static var bundledConfigURL: URL? {
        Bundle.main.url(forResource: "effects-default", withExtension: "json")
    }

    /// Source file in project directory (for development hot-reload)
    /// This is checked BEFORE the bundled copy during debug builds
    static var sourceConfigURL: URL? {
        #if DEBUG
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("dev/artdev/Hypnograph/Hypnograph/EffectLibrary/effects-default.json")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
        #else
        return nil
        #endif
    }

    // MARK: - Loading

    /// Result of loading effect chains
    struct LoadResult {
        let chains: [EffectChain]
        let source: Source
        let error: Error?

        enum Source {
            case user
            case bundled
            case hardcoded
        }
    }

    /// Load effect chains, with fallback chain: user config → source file (debug) → bundled → hardcoded
    static func loadChains() -> LoadResult {
        loadChainsWithDefinitions()
    }

    /// Load effect chains and cache for editing
    private static func loadChainsWithDefinitions() -> LoadResult {
        // Try user config first
        if FileManager.default.fileExists(atPath: userConfigURL.path) {
            do {
                let config = try loadConfigFromURL(userConfigURL)
                cachedConfig = config
                cachedConfigURL = userConfigURL
                updateSavedHash()
                return LoadResult(chains: config.effects, source: .user, error: nil)
            } catch {
                print("⚠️ EffectConfigLoader: Failed to load user config: \(error)")
                // Fall through to bundled
            }
        }

        // In debug builds, try source file (enables hot-reload during development)
        #if DEBUG
        if let sourceURL = sourceConfigURL {
            do {
                let config = try loadConfigFromURL(sourceURL)
                cachedConfig = config
                cachedConfigURL = sourceURL
                updateSavedHash()
                return LoadResult(chains: config.effects, source: .bundled, error: nil)
            } catch {
                print("⚠️ EffectConfigLoader: Failed to load source config: \(error)")
                // Fall through to bundled
            }
        }
        #endif

        // Try bundled default
        if let bundledURL = bundledConfigURL {
            do {
                let config = try loadConfigFromURL(bundledURL)
                cachedConfig = config
                cachedConfigURL = bundledURL
                updateSavedHash()
                return LoadResult(chains: config.effects, source: .bundled, error: nil)
            } catch {
                print("⚠️ EffectConfigLoader: Failed to load bundled config: \(error)")
                // Fall through to hardcoded
            }
        }

        // Hardcoded fallback
        print("ℹ️ EffectConfigLoader: Using hardcoded defaults")
        cachedConfig = nil
        cachedConfigURL = nil
        updateSavedHash()
        return LoadResult(chains: hardcodedDefaults, source: .hardcoded, error: nil)
    }

    /// Clear cached config (call on reload)
    static func clearCache() {
        cachedConfig = nil
        cachedConfigURL = nil
    }

    /// Load effect chains from a specific URL
    static func loadFromURL(_ url: URL) throws -> [EffectChain] {
        let config = try loadConfigFromURL(url)
        return config.effects
    }

    /// Load config from a specific URL
    private static func loadConfigFromURL(_ url: URL) throws -> EffectLibraryConfig {
        let data = try Data(contentsOf: url)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw LoadError.invalidEncoding
        }

        // Strip comments before parsing
        let cleanJSON = stripJSONComments(jsonString)
        guard let cleanData = cleanJSON.data(using: .utf8) else {
            throw LoadError.invalidEncoding
        }

        return try JSONDecoder().decode(EffectLibraryConfig.self, from: cleanData)
    }
    
    // MARK: - Comment Stripping (JSONC Support)
    
    /// Remove // and /* */ comments from JSON string
    static func stripJSONComments(_ json: String) -> String {
        var result = ""
        var inString = false
        var inLineComment = false
        var inBlockComment = false
        var i = json.startIndex
        
        while i < json.endIndex {
            let char = json[i]
            let nextIndex = json.index(after: i)
            let nextChar = nextIndex < json.endIndex ? json[nextIndex] : nil
            
            if inLineComment {
                if char == "\n" {
                    inLineComment = false
                    result.append(char)
                }
            } else if inBlockComment {
                if char == "*" && nextChar == "/" {
                    inBlockComment = false
                    i = json.index(after: nextIndex)
                    continue
                }
            } else if inString {
                result.append(char)
                if char == "\"" {
                    // Check if escaped
                    let prevIndex = json.index(before: i)
                    if prevIndex >= json.startIndex && json[prevIndex] != "\\" {
                        inString = false
                    }
                }
            } else {
                if char == "\"" {
                    inString = true
                    result.append(char)
                } else if char == "/" && nextChar == "/" {
                    inLineComment = true
                    i = nextIndex
                } else if char == "/" && nextChar == "*" {
                    inBlockComment = true
                    i = nextIndex
                } else {
                    result.append(char)
                }
            }
            i = json.index(after: i)
        }
        return result
    }
    
    // MARK: - Instantiation

    /// Instantiate Effects from an EffectChain.
    /// Public so recipes can instantiate effects from their stored chains.
    /// Returns a flat array of effects to apply in sequence.
    static func instantiateChain(_ chain: EffectChain) -> [Effect] {
        // Filter to enabled effects only
        let enabledEffects = chain.effects.filter { $0.isEnabled }

        // Instantiate each effect
        return enabledEffects.compactMap { instantiateEffectDef($0) }
    }

    /// Instantiate an Effect from an EffectDefinition
    static func instantiateEffectDef(_ effectDef: EffectDefinition) -> Effect? {
        // Check if disabled
        guard effectDef.isEnabled else { return nil }

        // Create from registry
        guard let effect = EffectRegistry.create(type: effectDef.type, params: effectDef.params) else {
            return nil
        }

        return effect
    }

    // MARK: - Errors

    enum LoadError: Error, LocalizedError {
        case invalidEncoding
        case fileNotFound

        var errorDescription: String? {
            switch self {
            case .invalidEncoding: return "Invalid file encoding"
            case .fileNotFound: return "Config file not found"
            }
        }
    }

    // MARK: - Hardcoded Fallback

    /// Last-resort fallback if no config files work
    static let hardcodedDefaults: [EffectChain] = [
        EffectChain(name: "RGB Split", effects: [
            EffectDefinition(type: "RGBSplitSimpleEffect", params: ["offsetAmount": .double(15.0), "animated": .bool(true)])
        ]),
        EffectChain(name: "Datamosh: Default", effects: [
            EffectDefinition(type: "DatamoshMetalEffect", params: nil)
        ]),
        EffectChain(name: "Hold Frame", effects: [
            EffectDefinition(type: "HoldFrameEffect", params: ["freezeInterval": .double(6.0), "holdDuration": .double(5.0), "trailBoost": .double(2.5)])
        ]),
        EffectChain(name: "Ghost Blur", effects: [
            EffectDefinition(type: "GhostBlurEffect", params: ["intensity": .double(0.2), "trailLength": .int(10), "blurAmount": .double(8.0)])
        ])
    ]
}

