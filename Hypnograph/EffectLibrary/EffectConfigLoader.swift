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
        let effects: [RenderHook]
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
        // Try user config first
        if FileManager.default.fileExists(atPath: userConfigURL.path) {
            do {
                let effects = try loadFromURL(userConfigURL)
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
                let effects = try loadFromURL(sourceURL)
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
                let effects = try loadFromURL(bundledURL)
                return LoadResult(effects: effects, source: .bundled, error: nil)
            } catch {
                print("⚠️ EffectConfigLoader: Failed to load bundled config: \(error)")
                // Fall through to hardcoded
            }
        }

        // Hardcoded fallback
        print("ℹ️ EffectConfigLoader: Using hardcoded defaults")
        return LoadResult(effects: hardcodedDefaults, source: .hardcoded, error: nil)
    }
    
    /// Load effects from a specific URL
    static func loadFromURL(_ url: URL) throws -> [RenderHook] {
        let data = try Data(contentsOf: url)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw LoadError.invalidEncoding
        }
        
        // Strip comments before parsing
        let cleanJSON = stripJSONComments(jsonString)
        guard let cleanData = cleanJSON.data(using: .utf8) else {
            throw LoadError.invalidEncoding
        }
        
        let config = try JSONDecoder().decode(EffectConfig.self, from: cleanData)
        return instantiateEffects(from: config)
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
    
    /// Convert parsed config to RenderHook instances
    private static func instantiateEffects(from config: EffectConfig) -> [RenderHook] {
        config.effects.compactMap { instantiateEffect($0) }
    }
    
    private static func instantiateEffect(_ def: EffectDefinition) -> RenderHook? {
        // Special handling for ChainedHook
        if def.type == "ChainedHook" {
            guard let childDefs = def.hooks, !childDefs.isEmpty else {
                print("⚠️ ChainedHook '\(def.name)' has no hooks")
                return nil
            }
            let childHooks = childDefs.compactMap { instantiateEffect($0) }
            guard !childHooks.isEmpty else { return nil }
            return ChainedHook(name: def.name, hooks: childHooks)
        }
        
        // Regular hook
        return EffectRegistry.create(type: def.type, params: def.params)
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
    static let hardcodedDefaults: [RenderHook] = [
        BlackAndWhiteHook(contrast: 1.0),
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

