//
//  EffectConfigLoader.swift
//  Hypnograph
//
//  JSON I/O utilities for effect configurations.
//  Supports JSONC (JSON with comments) via pre-parse stripping.
//
//  NOTE: This file now only contains I/O helpers and instantiation.
//  All editing/caching is handled by EffectsSession.
//

import Foundation

/// JSON I/O utilities for effect configurations
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
        // Try user config first
        if FileManager.default.fileExists(atPath: userConfigURL.path) {
            do {
                let config = try loadConfigFromURL(userConfigURL)
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
                return LoadResult(chains: config.effects, source: .bundled, error: nil)
            } catch {
                print("⚠️ EffectConfigLoader: Failed to load bundled config: \(error)")
                // Fall through to hardcoded
            }
        }

        // Fallback to bundled defaults via EffectsSession
        print("ℹ️ EffectConfigLoader: Using bundled defaults via EffectsSession")
        return LoadResult(chains: EffectsSession.loadBundledDefaults(), source: .hardcoded, error: nil)
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

}

