import SwiftUI
import AppKit

/// AppKit-backed panel toggle that keeps a familiar sliding-switch appearance for Studio.
struct PanelToggleView: NSViewRepresentable {
    @Binding var isOn: Bool

    @SwiftUI.Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> PanelToggleControl {
        let control = PanelToggleControl()
        control.onValueChanged = { newValue in
            isOn = newValue
        }
        return control
    }

    func updateNSView(_ nsView: PanelToggleControl, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onValueChanged = { newValue in
            isOn = newValue
        }
        nsView.setIsOn(isOn)
    }
}

final class PanelToggleControl: NSControl {
    var onValueChanged: ((Bool) -> Void)?

    private(set) var isOn = false

    private let trackWidth: CGFloat = 30
    private let trackHeight: CGFloat = 18
    private let thumbSize: CGFloat = 14
    private let horizontalPadding: CGFloat = 1

    override var intrinsicContentSize: NSSize {
        NSSize(width: trackWidth, height: trackHeight)
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    func setIsOn(_ newValue: Bool) {
        guard isOn != newValue else { return }
        isOn = newValue
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = NSRect(
            x: (bounds.width - trackWidth) * 0.5,
            y: (bounds.height - trackHeight) * 0.5,
            width: trackWidth,
            height: trackHeight
        )
        let thumbX = isOn
            ? trackRect.maxX - thumbSize - horizontalPadding
            : trackRect.minX + horizontalPadding
        let thumbRect = NSRect(
            x: thumbX,
            y: trackRect.midY - (thumbSize * 0.5),
            width: thumbSize,
            height: thumbSize
        )

        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: trackHeight * 0.5, yRadius: trackHeight * 0.5)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 1
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.set()

        let alpha: CGFloat = isEnabled ? 1.0 : 0.5
        let fillColor: NSColor = if isOn {
            .controlAccentColor.withAlphaComponent(alpha)
        } else {
            .white.withAlphaComponent(0.22 * alpha)
        }
        fillColor.setFill()
        trackPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let thumbPath = NSBezierPath(ovalIn: thumbRect)
        NSGraphicsContext.saveGraphicsState()
        let thumbShadow = NSShadow()
        thumbShadow.shadowBlurRadius = 2
        thumbShadow.shadowOffset = NSSize(width: 0, height: -1)
        thumbShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        thumbShadow.set()
        NSColor.white.withAlphaComponent(isEnabled ? 1.0 : 0.6).setFill()
        thumbPath.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            super.mouseDown(with: event)
            return
        }

        let newValue = !isOn
        isOn = newValue
        onValueChanged?(newValue)
        sendAction(action, to: target)
        needsDisplay = true
    }
}
