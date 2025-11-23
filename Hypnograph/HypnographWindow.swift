import AppKit

final class HypnographWindow: NSWindow {
    var onScroll: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
        // Don’t swallow it — let SwiftUI still see it if it wants.
        super.scrollWheel(with: event)
    }
}