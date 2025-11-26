//
//  RenderErrors.swift
//  Hypnograph
//
//  Typed errors for the render pipeline with clear, loggable messages
//

import Foundation
import AVFoundation

enum RenderError: Error, CustomStringConvertible {
    case noSources
    case invalidDuration(CMTime)
    case sourceLoadFailed(index: Int, url: URL, underlying: Error)
    case noVideoTrack(url: URL)
    case noAssetTrack(url: URL)
    case imageLoadFailed(url: URL, underlying: Error)
    case compositionBuildFailed(underlying: Error)
    case exportFailed(underlying: Error)
    case allSourcesFailedToLoad
    case invalidOutputSize(CGSize)
    case playerItemCreationFailed
    
    var description: String {
        switch self {
        case .noSources:
            return "RenderError: No sources provided in recipe"
            
        case .invalidDuration(let duration):
            return "RenderError: Invalid duration \(duration.seconds)s"
            
        case .sourceLoadFailed(let index, let url, let error):
            return "RenderError: Source[\(index)] failed to load from \(url.lastPathComponent): \(error.localizedDescription)"
            
        case .noVideoTrack(let url):
            return "RenderError: No video track found in \(url.lastPathComponent)"
            
        case .noAssetTrack(let url):
            return "RenderError: No asset track found in \(url.lastPathComponent)"
            
        case .imageLoadFailed(let url, let error):
            return "RenderError: Image failed to load from \(url.lastPathComponent): \(error.localizedDescription)"
            
        case .compositionBuildFailed(let error):
            return "RenderError: Composition build failed: \(error.localizedDescription)"
            
        case .exportFailed(let error):
            return "RenderError: Export failed: \(error.localizedDescription)"
            
        case .allSourcesFailedToLoad:
            return "RenderError: All sources failed to load"
            
        case .invalidOutputSize(let size):
            return "RenderError: Invalid output size \(size)"
            
        case .playerItemCreationFailed:
            return "RenderError: Failed to create AVPlayerItem"
        }
    }
    
    /// Log this error with context
    func log(context: String = "") {
        let prefix = context.isEmpty ? "" : "[\(context)] "
        print("🔴 \(prefix)\(description)")
    }
}

