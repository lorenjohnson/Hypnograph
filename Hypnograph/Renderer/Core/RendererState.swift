//
//  RendererState.swift
//  Hypnograph
//
//  Renderer readiness state for frame buffer prefilling.
//  Players observe this to know when temporal effects are ready.
//

import Foundation
import Combine

/// Renderer state for frame buffer prefilling
enum RendererReadinessState: Equatable {
    /// No temporal effects - ready immediately
    case ready
    
    /// Prefilling frame buffer (progress 0.0-1.0)
    case prefilling(progress: Double)
    
    /// Preroll failed
    case failed(reason: String)
    
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
    
    var isPrefilling: Bool {
        if case .prefilling = self { return true }
        return false
    }
    
    var progress: Double {
        if case .prefilling(let p) = self { return p }
        return isReady ? 1.0 : 0.0
    }
}

/// Observable renderer readiness for SwiftUI/Combine
@MainActor
final class RendererReadiness: ObservableObject {
    @Published private(set) var state: RendererReadinessState = .ready
    
    /// Set state to ready
    func setReady() {
        state = .ready
    }
    
    /// Set state to prefilling with progress
    func setPrefilling(progress: Double) {
        state = .prefilling(progress: progress)
    }
    
    /// Set state to failed
    func setFailed(reason: String) {
        state = .failed(reason: reason)
    }
    
    /// Reset to idle/ready state
    func reset() {
        state = .ready
    }
}

/// Player behavior when effects require frame buffer prefill
enum EffectBufferMode: String, CaseIterable {
    /// Start playback immediately, effect quality may be reduced initially
    case playWithEffect = "Play With Effect"
    
    /// Wait for frame buffer to fill before starting playback
    case waitForBuffer = "Wait for Effect Buffer"
    
    var localizedName: String { rawValue }
}

