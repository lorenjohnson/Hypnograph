//
//  CursorAutoHideView.swift
//  Hypnograph
//
//  Hides the mouse cursor after a period of mouse inactivity while playing video.
//

import SwiftUI
import AppKit

struct CursorAutoHideView: NSViewRepresentable {
    var isEnabled: Bool
    var idleSeconds: TimeInterval = 3.0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.startIfNeeded(isEnabled: isEnabled, idleSeconds: idleSeconds)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.startIfNeeded(isEnabled: isEnabled, idleSeconds: idleSeconds)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private var pollTimer: Timer?
        private var lastMouseLocation: NSPoint = NSEvent.mouseLocation
        private var lastMoveTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        private var isHiddenByUs: Bool = false
        private var isEnabled: Bool = false
        private var idleSeconds: TimeInterval = 3.0

        func startIfNeeded(isEnabled: Bool, idleSeconds: TimeInterval) {
            let idle = max(0.1, idleSeconds)

            if self.isEnabled != isEnabled || self.idleSeconds != idle {
                self.isEnabled = isEnabled
                self.idleSeconds = idle

                if !isEnabled {
                    stop()
                    return
                }
            }

            guard isEnabled else { return }
            startPollingIfNeeded()
        }

        func stop() {
            pollTimer?.invalidate()
            pollTimer = nil

            // If we hid it, restore immediately so pausing doesn't require "wiggle to reveal".
            unhideIfNeeded()

            isEnabled = false
        }

        private func startPollingIfNeeded() {
            guard pollTimer == nil else { return }

            lastMouseLocation = NSEvent.mouseLocation
            lastMoveTime = CFAbsoluteTimeGetCurrent()

            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self, self.isEnabled else { return }
                self.pollOnce()
            }
            RunLoop.main.add(pollTimer!, forMode: .common)
        }

        private func pollOnce() {
            guard NSApp.isActive else {
                unhideIfNeeded()
                return
            }

            let now = CFAbsoluteTimeGetCurrent()
            let loc = NSEvent.mouseLocation

            if loc.x != lastMouseLocation.x || loc.y != lastMouseLocation.y {
                lastMouseLocation = loc
                lastMoveTime = now
                unhideIfNeeded()
                return
            }

            let idleFor = now - lastMoveTime
            if idleFor >= idleSeconds {
                hideIfNeeded()
            }
        }

        private func hideIfNeeded() {
            guard !isHiddenByUs else { return }
            NSCursor.hide()
            isHiddenByUs = true
        }

        private func unhideIfNeeded() {
            guard isHiddenByUs else { return }
            NSCursor.unhide()
            isHiddenByUs = false
        }
    }
}
