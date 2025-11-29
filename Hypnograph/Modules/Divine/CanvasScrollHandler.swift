//
//  CanvasScrollHandler.swift
//  Hypnograph
//
//  Handles mouse wheel → zoom/pan for Divine mode.
//  Attach via .overlay(...) in SwiftUI.
//

import SwiftUI
import AppKit

struct CanvasScrollHandler: NSViewRepresentable {
    let onZoom: (CGFloat) -> Void
    let onPan: (CGSize) -> Void

    func makeNSView(context: Context) -> NSView {
        CanvasScrollNSView(onZoom: onZoom, onPan: onPan)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No dynamic updates needed
    }

    private final class CanvasScrollNSView: NSView {
        private let onZoom: (CGFloat) -> Void
        private let onPan: (CGSize) -> Void

        init(
            onZoom: @escaping (CGFloat) -> Void,
            onPan: @escaping (CGSize) -> Void
        ) {
            self.onZoom = onZoom
            self.onPan = onPan
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            // Defer to next runloop so window & responder chain are stable.
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // This is what should cause scrollWheel events to come here.
                self.window?.makeFirstResponder(self)
                // Debug:
                print("CanvasScrollNSView: requested first responder (window=\(String(describing: self.window)))")
            }
        }

        override func scrollWheel(with event: NSEvent) {
            // Debug logging so you can confirm this is firing at all.
            print("CanvasScrollNSView: scrollWheel delta=(x:\(event.scrollingDeltaX), y:\(event.scrollingDeltaY)), flags=\(event.modifierFlags.rawValue)")

            let flags = event.modifierFlags
            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY

            // Cmd + wheel => zoom
            if flags.contains(.command) {
                onZoom(deltaY)
                return
            }

            // Otherwise => pan
            var pan = CGSize.zero

            if flags.contains(.shift) {
                // Shift + wheel: horizontal pan (use vertical wheel when present)
                let horizontal = deltaY != 0 ? deltaY : deltaX
                pan.width = horizontal
            } else {
                // Normal: vertical pan + trackpad horizontal if any
                pan.height = deltaY
                pan.width = deltaX
            }

            if pan != .zero {
                onPan(pan)
            }
        }
    }
}
