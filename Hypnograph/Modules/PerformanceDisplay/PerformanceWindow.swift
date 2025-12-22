//
//  PerformanceWindow.swift
//  Hypnograph
//
//  Custom NSWindow for the performance display.
//  Borderless, fullscreen-capable, designed for external monitor output.
//

import AppKit
import AVKit

/// Borderless window for clean performance output
/// Does not steal focus from the main window
final class PerformanceWindow: NSWindow {

    // Don't steal keyboard focus from main window
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func configureForPerformance() {
        // Hide title bar
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        // Black background
        backgroundColor = .black
    }
}

/// Content view containing the A/B player views for crossfading
final class PerformanceContentView: NSView {
    
    /// Player view A
    let playerA: AVPlayerView
    
    /// Player view B
    let playerB: AVPlayerView
    
    override init(frame frameRect: NSRect) {
        // Create player views
        playerA = AVPlayerView(frame: frameRect)
        playerB = AVPlayerView(frame: frameRect)
        
        super.init(frame: frameRect)
        
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        
        // Configure player views
        for playerView in [playerA, playerB] {
            playerView.controlsStyle = .none
            playerView.videoGravity = .resizeAspect
            playerView.translatesAutoresizingMaskIntoConstraints = false
            playerView.wantsLayer = true
            playerView.layer?.backgroundColor = NSColor.black.cgColor
            // Remove AVPlayerView's default background
            playerView.contentOverlayView?.wantsLayer = true
            playerView.contentOverlayView?.layer?.backgroundColor = NSColor.clear.cgColor
            addSubview(playerView)

            // Fill parent
            NSLayoutConstraint.activate([
                playerView.topAnchor.constraint(equalTo: topAnchor),
                playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
                playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }
        
        // Start with both invisible
        playerA.alphaValue = 0
        playerB.alphaValue = 0
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Get list of available external screens
    static var externalScreens: [NSScreen] {
        NSScreen.screens.filter { $0 != NSScreen.main }
    }
    
    /// Get the best screen for performance display (prefers external)
    static var preferredScreen: NSScreen {
        externalScreens.first ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

