import SwiftUI
import AppKit

/// Tracks mouse inactivity and toggles overlay visibility using the same idle timing as cursor auto-hide.
struct MouseIdleVisibilityView: NSViewRepresentable {
    var isEnabled: Bool
    var idleSeconds: TimeInterval = 3.0
    @Binding var isVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isVisible: $isVisible)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.startIfNeeded(isEnabled: isEnabled, idleSeconds: idleSeconds)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.binding = $isVisible
        context.coordinator.startIfNeeded(isEnabled: isEnabled, idleSeconds: idleSeconds)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        fileprivate var binding: Binding<Bool>
        private var pollTimer: Timer?
        private var lastMouseLocation: NSPoint = NSEvent.mouseLocation
        private var lastMoveTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        private var isEnabled: Bool = false
        private var idleSeconds: TimeInterval = 3.0

        init(isVisible: Binding<Bool>) {
            self.binding = isVisible
        }

        func startIfNeeded(isEnabled: Bool, idleSeconds: TimeInterval) {
            let idle = max(0.1, idleSeconds)

            if self.isEnabled != isEnabled || self.idleSeconds != idle {
                self.isEnabled = isEnabled
                self.idleSeconds = idle

                if !isEnabled {
                    stop()
                    binding.wrappedValue = true
                    return
                }
            }

            guard isEnabled else { return }
            startPollingIfNeeded()
        }

        func stop() {
            pollTimer?.invalidate()
            pollTimer = nil
            isEnabled = false
        }

        private func startPollingIfNeeded() {
            guard pollTimer == nil else { return }

            lastMouseLocation = NSEvent.mouseLocation
            lastMoveTime = CFAbsoluteTimeGetCurrent()
            binding.wrappedValue = true

            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                self?.pollOnce()
            }
            if let pollTimer {
                RunLoop.main.add(pollTimer, forMode: .common)
            }
        }

        private func pollOnce() {
            guard isEnabled else { return }

            guard NSApp.isActive else {
                binding.wrappedValue = true
                return
            }

            let now = CFAbsoluteTimeGetCurrent()
            let location = NSEvent.mouseLocation
            if location.x != lastMouseLocation.x || location.y != lastMouseLocation.y {
                lastMouseLocation = location
                lastMoveTime = now
                binding.wrappedValue = true
                return
            }

            binding.wrappedValue = (now - lastMoveTime) < idleSeconds
        }
    }
}
