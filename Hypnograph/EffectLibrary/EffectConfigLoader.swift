//
//  EffectConfigLoader.swift
//  Hypnograph
//
//  Loads and parses effect configuration from JSON files.
//  Supports JSONC (JSON with comments) via pre-parse stripping.
//

import Foundation

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
        _ = loadEffectsWithDefinitions()
        return cachedConfig?.effects ?? []
    }

    /// @deprecated Use currentChains instead
    static var currentDefinitions: [EffectChain] { currentChains }

    /// Callback for live effect application (set by EffectManager)
    static var onEffectUpdated: ((Int, Effect) -> Void)?

    /// Debounce timer for async file save AND effect instantiation
    private static var saveTimer: Timer?
    private static let saveDebounceInterval: TimeInterval = 0.3

    /// Track which effects need re-instantiation
    private static var pendingInstantiations: Set<Int> = []

    /// Update a hook's parameter value - updates cache immediately, defers instantiation and save
    static func updateParameter(effectIndex: Int, hookIndex: Int?, paramName: String, value: AnyCodableValue) {
        guard var config = cachedConfig else { return }
        guard effectIndex >= 0 && effectIndex < config.effects.count else { return }

        var chain = config.effects[effectIndex]

        if let hookIdx = hookIndex {
            // Update a hook's parameter
            guard hookIdx >= 0 && hookIdx < chain.hooks.count else { return }
            var params = chain.hooks[hookIdx].params ?? [:]
            params[paramName] = value
            chain.hooks[hookIdx].params = params
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
        scheduleInstantiationAndSave(effectIndex: effectIndex, config: config)
    }

    /// Add a hook to an effect chain
    static func addHookToChain(effectIndex: Int, hookType: String) {
        guard var config = cachedConfig else { return }
        guard effectIndex >= 0 && effectIndex < config.effects.count else { return }

        var chain = config.effects[effectIndex]

        // Create new hook with default params from registry
        let defaultParams = EffectRegistry.defaults(for: hookType)
        let newHook = HookDefinition(type: hookType, params: defaultParams)
        chain.hooks.append(newHook)

        var effects = config.effects
        effects[effectIndex] = chain
        config = EffectLibraryConfig(version: config.version, effects: effects)
        cachedConfig = config

        scheduleInstantiationAndSave(effectIndex: effectIndex, config: config)
    }

    /// Remove a hook from an effect chain
    static func removeHookFromChain(effectIndex: Int, hookIndex: Int) {
        guard var config = cachedConfig else { return }
        guard effectIndex >= 0 && effectIndex < config.effects.count else { return }

        var chain = config.effects[effectIndex]
        guard hookIndex >= 0 && hookIndex < chain.hooks.count else { return }

        chain.hooks.remove(at: hookIndex)

        var effects = config.effects
        effects[effectIndex] = chain
        config = EffectLibraryConfig(version: config.version, effects: effects)
        cachedConfig = config

        scheduleInstantiationAndSave(effectIndex: effectIndex, config: config)
    }

    /// Create a new effect chain with BasicHook as default
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

        // Create chain with BasicHook as default hook
        let basicDefaults = EffectRegistry.defaults(for: "BasicHook")
        let basicHook = HookDefinition(type: "BasicHook", params: basicDefaults)
        let newChain = EffectChain(name: uniqueName, hooks: [basicHook])

        var effects = config.effects
        effects.append(newChain)
        config = EffectLibraryConfig(version: config.version, effects: effects)
        cachedConfig = config

        // Reload EffectChainLibrary.all to include the new chain
        reloadEffectAll()

        scheduleSave(config)
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

        scheduleSave(config)
    }

    /// Reload EffectChainLibrary.all from cached config
    /// This directly updates EffectChainLibrary's cache without clearing our in-memory config
    private static func reloadEffectAll() {
        guard let config = cachedConfig else { return }
        let hooks = instantiateEffects(from: config)

        // Directly update EffectChainLibrary's cached result without going through reload()
        // which would clear our in-memory config
        EffectChainLibrary.updateCache(with: hooks)
    }

    /// Reorder hooks in an effect chain
    static func reorderHooksInChain(effectIndex: Int, fromIndex: Int, toIndex: Int) {
        guard var config = cachedConfig else { return }
        guard effectIndex >= 0 && effectIndex < config.effects.count else { return }

        var chain = config.effects[effectIndex]
        guard fromIndex >= 0 && fromIndex < chain.hooks.count else { return }
        guard toIndex >= 0 && toIndex < chain.hooks.count else { return }

        let hook = chain.hooks.remove(at: fromIndex)
        chain.hooks.insert(hook, at: toIndex)

        var effects = config.effects
        effects[effectIndex] = chain
        config = EffectLibraryConfig(version: config.version, effects: effects)
        cachedConfig = config

        scheduleInstantiationAndSave(effectIndex: effectIndex, config: config)
    }

    /// Toggle hook enabled state (stored as _enabled param)
    static func setHookEnabled(effectIndex: Int, hookIndex: Int, enabled: Bool) {
        updateParameter(effectIndex: effectIndex, hookIndex: hookIndex, paramName: "_enabled", value: .bool(enabled))
    }

    /// Reset a hook's parameters to their default values
    static func resetHookToDefaults(effectIndex: Int, hookIndex: Int) {
        guard var config = cachedConfig else { return }
        guard effectIndex >= 0 && effectIndex < config.effects.count else { return }

        var chain = config.effects[effectIndex]
        guard hookIndex >= 0 && hookIndex < chain.hooks.count else { return }

        let hook = chain.hooks[hookIndex]

        // Get defaults, preserve _enabled state
        var defaults = EffectRegistry.defaults(for: hook.type)
        if let wasEnabled = hook.params?["_enabled"] {
            defaults["_enabled"] = wasEnabled
        }

        chain.hooks[hookIndex].params = defaults

        var effects = config.effects
        effects[effectIndex] = chain
        config = EffectLibraryConfig(version: config.version, effects: effects)
        cachedConfig = config

        scheduleInstantiationAndSave(effectIndex: effectIndex, config: config)
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

        scheduleInstantiationAndSave(effectIndex: effectIndex, config: config)
    }

    /// Schedule debounced instantiation AND file save
    /// Batches multiple rapid changes into a single heavy operation
    private static func scheduleInstantiationAndSave(effectIndex: Int, config: EffectLibraryConfig) {
        // Track which chains need re-instantiation
        pendingInstantiations.insert(effectIndex)

        // Cancel any pending timer
        saveTimer?.invalidate()

        // Schedule combined instantiation + save after debounce interval
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceInterval, repeats: false) { _ in
            performPendingInstantiations()
            saveToFile(config)
        }
    }

    /// Perform all pending instantiations in one batch
    private static func performPendingInstantiations() {
        guard let config = cachedConfig else {
            pendingInstantiations.removeAll()
            return
        }

        for effectIndex in pendingInstantiations {
            guard effectIndex >= 0 && effectIndex < config.effects.count else { continue }
            let chain = config.effects[effectIndex]
            if let newEffect = instantiateChain(chain) {
                onEffectUpdated?(effectIndex, newEffect)
            }
        }
        pendingInstantiations.removeAll()
    }

    /// Schedule a debounced save to file (for operations that don't need re-instantiation)
    private static func scheduleSave(_ config: EffectLibraryConfig) {
        // Cancel any pending save
        saveTimer?.invalidate()

        // Schedule new save after debounce interval
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceInterval, repeats: false) { _ in
            saveToFile(config)
        }
    }

    /// Save config to file asynchronously
    /// Always saves to userConfigURL (Application Support), regardless of where we loaded from
    private static func saveToFile(_ config: EffectLibraryConfig) {
        let url = userConfigURL

        // Save on background queue
        DispatchQueue.global(qos: .utility).async {
            do {
                // Ensure directory exists
                let directory = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(config)
                try data.write(to: url)
                print("✓ Effects saved to \(url.path)")
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
    
    /// Result of loading effects
    struct LoadResult {
        let effects: [Effect]
        let source: Source
        let error: Error?
        
        enum Source {
            case user
            case bundled
            case hardcoded
        }
    }
    
    /// Load effects, with fallback chain: user config → source file (debug) → bundled → hardcoded
    static func loadEffects() -> LoadResult {
        loadEffectsWithDefinitions()
    }

    /// Load effects and cache definitions for editing
    private static func loadEffectsWithDefinitions() -> LoadResult {
        // Try user config first
        if FileManager.default.fileExists(atPath: userConfigURL.path) {
            do {
                let (effects, config) = try loadFromURLWithConfig(userConfigURL)
                cachedConfig = config
                cachedConfigURL = userConfigURL
                return LoadResult(effects: effects, source: .user, error: nil)
            } catch {
                print("⚠️ EffectConfigLoader: Failed to load user config: \(error)")
                // Fall through to bundled
            }
        }

        // In debug builds, try source file (enables hot-reload during development)
        #if DEBUG
        if let sourceURL = sourceConfigURL {
            do {
                let (effects, config) = try loadFromURLWithConfig(sourceURL)
                cachedConfig = config
                cachedConfigURL = sourceURL
                return LoadResult(effects: effects, source: .bundled, error: nil)
            } catch {
                print("⚠️ EffectConfigLoader: Failed to load source config: \(error)")
                // Fall through to bundled
            }
        }
        #endif

        // Try bundled default
        if let bundledURL = bundledConfigURL {
            do {
                let (effects, config) = try loadFromURLWithConfig(bundledURL)
                cachedConfig = config
                cachedConfigURL = bundledURL
                return LoadResult(effects: effects, source: .bundled, error: nil)
            } catch {
                print("⚠️ EffectConfigLoader: Failed to load bundled config: \(error)")
                // Fall through to hardcoded
            }
        }

        // Hardcoded fallback
        print("ℹ️ EffectConfigLoader: Using hardcoded defaults")
        cachedConfig = nil
        cachedConfigURL = nil
        return LoadResult(effects: hardcodedDefaults, source: .hardcoded, error: nil)
    }

    /// Clear cached config (call on reload)
    static func clearCache() {
        cachedConfig = nil
        cachedConfigURL = nil
    }

    /// Load effects from a specific URL
    static func loadFromURL(_ url: URL) throws -> [Effect] {
        let (effects, _) = try loadFromURLWithConfig(url)
        return effects
    }

    /// Load effects from a specific URL and return both effects and raw config
    private static func loadFromURLWithConfig(_ url: URL) throws -> ([Effect], EffectLibraryConfig) {
        let data = try Data(contentsOf: url)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw LoadError.invalidEncoding
        }

        // Strip comments before parsing
        let cleanJSON = stripJSONComments(jsonString)
        guard let cleanData = cleanJSON.data(using: .utf8) else {
            throw LoadError.invalidEncoding
        }

        let config = try JSONDecoder().decode(EffectLibraryConfig.self, from: cleanData)
        return (instantiateEffects(from: config), config)
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

    /// Convert parsed config to Effect instances
    private static func instantiateEffects(from config: EffectLibraryConfig) -> [Effect] {
        config.effects.compactMap { instantiateChain($0) }
    }

    /// Instantiate an Effect from an EffectChain.
    /// Public so recipes can instantiate effects from their stored chains.
    static func instantiateChain(_ chain: EffectChain) -> Effect? {
        // Filter to enabled hooks only
        let enabledHooks = chain.hooks.filter { $0.isEnabled }

        // Instantiate each hook
        let childEffects = enabledHooks.compactMap { instantiateHook($0) }

        // Return ChainedHook even if empty - keeps effect list indices stable
        // An empty ChainedHook acts as a pass-through
        return ChainedHook(name: chain.name ?? "Chain", hooks: childEffects)
    }

    /// Instantiate an Effect from a HookDefinition
    static func instantiateHook(_ hook: HookDefinition) -> Effect? {
        // Check if disabled
        guard hook.isEnabled else { return nil }

        // Create from registry
        guard let effect = EffectRegistry.create(type: hook.type, params: hook.params) else {
            return nil
        }

        return effect
    }

    /// @deprecated Use instantiateChain instead
    static func instantiateEffect(_ def: EffectChain) -> Effect? {
        instantiateChain(def)
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
    static let hardcodedDefaults: [Effect] = [
        RGBSplitSimpleHook(offsetAmount: 15.0, animated: true),
        ChainedHook(name: "Datamosh: Default", hooks: [
            DatamoshMetalHook(params: .default)
        ]),
        ChainedHook(name: "Datamosh: Subtle", hooks: [
            DatamoshMetalHook(params: .subtle)
        ]),
        ChainedHook(name: "Hold + Ghost", hooks: [
            HoldFrameHook(freezeInterval: 6.0, holdDuration: 5.0, trailBoost: 2.5),
            GhostBlurHook(intensity: 0.2, trailLength: 10, blurAmount: 8.0)
        ])
    ]
}

