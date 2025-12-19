//
//  EffectConfigWatcher.swift
//  Hypnograph
//
//  Watches effect config files for changes and auto-reloads.
//  Monitors both bundled default and user config in Application Support.
//

import Foundation

/// Watches effect config files and triggers reload on changes
final class EffectConfigWatcher {
    
    static let shared = EffectConfigWatcher()
    
    // MARK: - State
    
    private var watchedSources: [FileDescriptor: DispatchSourceFileSystemObject] = [:]
    private var isWatching = false
    
    /// Debounce to avoid multiple reloads for rapid changes
    private var debounceTask: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.5
    
    // MARK: - File Descriptor wrapper
    
    private struct FileDescriptor: Hashable {
        let fd: Int32
        let url: URL
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Start watching both config files
    func startWatching() {
        guard !isWatching else { return }
        isWatching = true

        // Watch bundled default (for development - inside .app bundle)
        if let bundledURL = EffectConfigLoader.bundledConfigURL {
            watchFile(at: bundledURL, label: "bundled")
        }

        // In debug builds, also watch the source file in the project directory
        // This enables hot-reload during development when editing in Xcode
        #if DEBUG
        if let sourceURL = findSourceFileURL() {
            watchFile(at: sourceURL, label: "source")
            print("👁️ EffectConfigWatcher: Watching source file at \(sourceURL.path)")
        }
        #endif

        // Watch user config in Application Support
        let userURL = EffectConfigLoader.userConfigURL
        ensureDirectoryExists(for: userURL)
        watchFile(at: userURL, label: "user")
        // Also watch the directory in case file is created/deleted
        watchDirectory(at: userURL.deletingLastPathComponent(), label: "user-dir")

        print("👁️ EffectConfigWatcher: Started watching config files")
    }

    /// Find the source file in the project directory (for development hot-reload)
    /// Walks up from the app bundle to find the project source
    private func findSourceFileURL() -> URL? {
        // The app bundle is at something like:
        // ~/Library/Developer/Xcode/DerivedData/Hypnograph-xxx/Build/Products/Debug/Hypnograph.app
        // We need to find the project source at:
        // ~/dev/artdev/Hypnograph/Hypnograph/EffectLibrary/effects-default.json

        // Try common development paths
        let possiblePaths = [
            // Direct path if we know the project location
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("dev/artdev/Hypnograph/Hypnograph/EffectLibrary/effects-default.json"),
            // Relative from bundle (won't work for Xcode builds but might for command line)
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Hypnograph/EffectLibrary/effects-default.json")
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }

        return nil
    }
    
    /// Stop watching all files
    func stopWatching() {
        guard isWatching else { return }
        isWatching = false
        
        for (descriptor, source) in watchedSources {
            source.cancel()
            close(descriptor.fd)
        }
        watchedSources.removeAll()
        
        print("👁️ EffectConfigWatcher: Stopped watching")
    }
    
    // MARK: - Private
    
    private func ensureDirectoryExists(for fileURL: URL) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    
    private func watchFile(at url: URL, label: String) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File doesn't exist yet - that's OK, directory watcher will catch creation
            print("👁️ EffectConfigWatcher: \(label) config not found (will watch for creation)")
            return
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        
        source.setEventHandler { [weak self] in
            self?.handleFileChange(url: url, label: label)
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        let descriptor = FileDescriptor(fd: fd, url: url)
        watchedSources[descriptor] = source
        source.resume()
        
        print("👁️ EffectConfigWatcher: Watching \(label) config at \(url.path)")
    }
    
    private func watchDirectory(at url: URL, label: String) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write],
            queue: .main
        )
        
        source.setEventHandler { [weak self] in
            // Directory changed - check if user config was created
            let userURL = EffectConfigLoader.userConfigURL
            if FileManager.default.fileExists(atPath: userURL.path) {
                // Re-watch the file if it now exists
                self?.watchFile(at: userURL, label: "user")
            }
            self?.handleFileChange(url: url, label: label)
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        let descriptor = FileDescriptor(fd: fd, url: url)
        watchedSources[descriptor] = source
        source.resume()
    }
    
    private func handleFileChange(url: URL, label: String) {
        // Debounce rapid changes
        debounceTask?.cancel()
        
        let task = DispatchWorkItem { [weak self] in
            guard self?.isWatching == true else { return }
            print("👁️ EffectConfigWatcher: Detected change in \(label) config")
            Effect.reload()
        }
        
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: task)
    }
}

