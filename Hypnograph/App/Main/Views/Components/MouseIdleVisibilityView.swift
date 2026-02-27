import SwiftUI
import AppKit

/// Tracks mouse inactivity and toggles overlay visibility using the same idle timing as cursor auto-hide.
struct MouseIdleVisibilityView: NSViewRepresentable {
    var isEnabled: Bool
    var idleSeconds: TimeInterval = 3.0
    var startHiddenOnEnable: Bool = false
    var activityIgnoreLeftInset: CGFloat = 0
    var activityIgnoreRightInset: CGFloat = 0
    @Binding var isVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isVisible: $isVisible)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.startIfNeeded(
            isEnabled: isEnabled,
            idleSeconds: idleSeconds,
            startHiddenOnEnable: startHiddenOnEnable,
            activityIgnoreLeftInset: activityIgnoreLeftInset,
            activityIgnoreRightInset: activityIgnoreRightInset
        )
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.binding = $isVisible
        context.coordinator.startIfNeeded(
            isEnabled: isEnabled,
            idleSeconds: idleSeconds,
            startHiddenOnEnable: startHiddenOnEnable,
            activityIgnoreLeftInset: activityIgnoreLeftInset,
            activityIgnoreRightInset: activityIgnoreRightInset
        )
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
        private var startHiddenOnEnable: Bool = false
        private var activityIgnoreLeftInset: CGFloat = 0
        private var activityIgnoreRightInset: CGFloat = 0

        init(isVisible: Binding<Bool>) {
            self.binding = isVisible
        }

        func startIfNeeded(
            isEnabled: Bool,
            idleSeconds: TimeInterval,
            startHiddenOnEnable: Bool,
            activityIgnoreLeftInset: CGFloat,
            activityIgnoreRightInset: CGFloat
        ) {
            let idle = max(0.1, idleSeconds)
            let hiddenModeChanged = self.startHiddenOnEnable != startHiddenOnEnable
            let activityInsetsChanged =
                self.activityIgnoreLeftInset != activityIgnoreLeftInset ||
                self.activityIgnoreRightInset != activityIgnoreRightInset
            self.startHiddenOnEnable = startHiddenOnEnable
            self.activityIgnoreLeftInset = max(0, activityIgnoreLeftInset)
            self.activityIgnoreRightInset = max(0, activityIgnoreRightInset)

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
            if (hiddenModeChanged || activityInsetsChanged), pollTimer != nil {
                lastMouseLocation = NSEvent.mouseLocation
                if startHiddenOnEnable {
                    lastMoveTime = CFAbsoluteTimeGetCurrent() - idleSeconds
                    binding.wrappedValue = false
                } else {
                    lastMoveTime = CFAbsoluteTimeGetCurrent()
                    binding.wrappedValue = true
                }
            }
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
            if startHiddenOnEnable {
                // For clean-screen entry, start hidden so keyboard toggles do not count as "activity".
                lastMoveTime = CFAbsoluteTimeGetCurrent() - idleSeconds
                binding.wrappedValue = false
            } else {
                // In normal mode, begin visible and hide after idle timeout.
                lastMoveTime = CFAbsoluteTimeGetCurrent()
                binding.wrappedValue = true
            }

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
                if isInsideActivityRegion(location: location) {
                    lastMoveTime = now
                    binding.wrappedValue = true
                }
                return
            }

            binding.wrappedValue = (now - lastMoveTime) < idleSeconds
        }

        private func isInsideActivityRegion(location: NSPoint) -> Bool {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return true }
            let frame = window.frame
            guard frame.width > 0 else { return true }

            let localX = location.x - frame.minX
            guard localX >= 0, localX <= frame.width else { return false }

            let leftBoundary = min(activityIgnoreLeftInset, frame.width)
            let rightBoundary = max(leftBoundary, frame.width - min(activityIgnoreRightInset, frame.width))
            return localX >= leftBoundary && localX <= rightBoundary
        }
    }
}
