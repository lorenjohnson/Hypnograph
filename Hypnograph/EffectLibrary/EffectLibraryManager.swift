//
//  EffectLibraryManager.swift
//  Hypnograph
//
//  Manages switching between effect library JSON files.
//  Scans effect-libraries folder and allows runtime switching.
//

import Foundation
import Combine

/// Represents an available effect library
struct EffectLibrary: Identifiable, Hashable {
    let id: String           // Unique identifier (filename or "default")
    let displayName: String  // Human-readable name
    let url: URL?            // nil for default (uses bundled/source file)
    
    var isDefault: Bool { id == "default" }
}

/// Manages available effect libraries and current selection
@MainActor
final class EffectLibraryManager: ObservableObject {
    
    static let shared = EffectLibraryManager()
    
    /// Currently selected library
    @Published private(set) var currentLibrary: EffectLibrary
    
    /// All available libraries (default + any in effect-libraries folder)
    @Published private(set) var availableLibraries: [EffectLibrary] = []
    
    /// Directory where custom effect libraries live
    nonisolated static var librariesDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Hypnograph/effect-libraries", isDirectory: true)
    }
    
    private init() {
        // Start with default
        let defaultLib = EffectLibrary(id: "default", displayName: "Default", url: nil)
        self.currentLibrary = defaultLib
        self.availableLibraries = [defaultLib]
        
        // Scan for additional libraries
        scanForLibraries()
    }
    
    // MARK: - Scanning
    
    /// Scan the effect-libraries folder for JSON files
    func scanForLibraries() {
        var libraries: [EffectLibrary] = []
        
        // Always include default first
        libraries.append(EffectLibrary(id: "default", displayName: "Default", url: nil))
        
        // Ensure directory exists
        let dirURL = Self.librariesDirectoryURL
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        
        // Scan for .json files
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            for fileURL in contents where fileURL.pathExtension == "json" {
                let filename = fileURL.deletingPathExtension().lastPathComponent
                // Create display name from filename (replace - and _ with spaces, title case)
                let displayName = filename
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
                
                libraries.append(EffectLibrary(
                    id: fileURL.lastPathComponent,
                    displayName: displayName,
                    url: fileURL
                ))
            }
        } catch {
            print("⚠️ EffectLibraryManager: Failed to scan libraries folder: \(error)")
        }
        
        availableLibraries = libraries
        
        // If current library no longer exists, reset to default
        if !libraries.contains(where: { $0.id == currentLibrary.id }) {
            currentLibrary = libraries.first!
        }
        
        print("📚 EffectLibraryManager: Found \(libraries.count) libraries")
    }
    
    // MARK: - Selection
    
    /// Switch to a different effect library
    func selectLibrary(_ library: EffectLibrary) {
        guard library.id != currentLibrary.id else { return }
        
        currentLibrary = library
        
        // Reload effects from the new library
        reloadEffectsFromCurrentLibrary()
        
        let name = library.displayName
        print("📚 Switched to effect library: \(name)")
        AppNotifications.show("Effects: \(name)", flash: true, duration: 2.0)
    }
    
    /// Select library by ID
    func selectLibrary(id: String) {
        guard let library = availableLibraries.first(where: { $0.id == id }) else {
            print("⚠️ EffectLibraryManager: Library '\(id)' not found")
            return
        }
        selectLibrary(library)
    }
    
    // MARK: - Loading
    
    /// Reload effects from the currently selected library
    func reloadEffectsFromCurrentLibrary() {
        if currentLibrary.isDefault {
            // Use normal loading (source file in debug, bundled in release)
            EffectChainLibrary.reload()
        } else if let url = currentLibrary.url {
            // Load from specific file
            EffectChainLibrary.reload(from: url)
        }
    }
    
    /// Get the URL that should be used for loading effects
    var currentLibraryURL: URL? {
        currentLibrary.url
    }
}

