import SwiftUI
import AppKit

/// AppKit-backed single-value slider for Studio panels.
/// Matches the visual language of `RangeSliderView` and avoids window-drag conflicts.
struct PanelSliderView: NSViewRepresentable {
    @Binding var value: Double
    let bounds: ClosedRange<Double>

    var step: Double = 0
    var snapMarkers: [Double] = []
    var thumbDiameter: CGFloat = 16
    var fillColor: NSColor = .controlAccentColor
    var onEditingChanged: ((Bool) -> Void)? = nil

    @SwiftUI.Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> PanelSliderControl {
        let control = PanelSliderControl()
        control.onValueChanged = { newValue in
            value = newValue
        }
        control.onEditingChanged = { isEditing in
            onEditingChanged?(isEditing)
        }
        return control
    }

    func updateNSView(_ nsView: PanelSliderControl, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.sliderBounds = bounds
        nsView.step = step
        nsView.snapMarkers = snapMarkers
        nsView.thumbDiameter = thumbDiameter
        nsView.fillColor = fillColor
        nsView.onValueChanged = { newValue in
            value = newValue
        }
        nsView.onEditingChanged = { isEditing in
            onEditingChanged?(isEditing)
        }
        nsView.setValue(value)
    }
}

final class PanelSliderControl: NSControl {
    var sliderBounds: ClosedRange<Double> = 0...1 {
        didSet { needsDisplay = true }
    }

    var step: Double = 0 {
        didSet { needsDisplay = true }
    }

    var snapMarkers: [Double] = [] {
        didSet { needsDisplay = true }
    }

    var onValueChanged: ((Double) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?

    private(set) var currentValue: Double = 0
    private var isTrackingThumb = false

    var thumbDiameter: CGFloat = 16 {
        didSet {
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }
    var fillColor: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }
    private let trackHeight: CGFloat = 4
    private let markerDiameter: CGFloat = 3
    private let markerSpacing: CGFloat = 6
    private let maxAutoMarkerCount = 24

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: effectiveSnapMarkers.isEmpty ? 20 : 26)
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    func setValue(_ newValue: Double) {
        let clamped = snapped(newValue).clamped(to: sliderBounds)
        guard abs(currentValue - clamped) > 0.0001 else { return }
        currentValue = clamped
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = self.trackRect
        let centerX = xPosition(for: currentValue, usableWidth: usableWidth)

        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        NSColor.secondaryLabelColor.withAlphaComponent(0.3).setFill()
        trackPath.fill()

        drawSnapMarkers()

        let selectionRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: max(thumbDiameter * 0.5, centerX - trackRect.minX),
            height: trackRect.height
        )
        let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        fillColor.setFill()
        selectionPath.fill()

        drawThumb(centerX: centerX, active: isTrackingThumb)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            super.mouseDown(with: event)
            return
        }

        isTrackingThumb = true
        onEditingChanged?(true)
        updateValue(with: convert(event.locationInWindow, from: nil))
        needsDisplay = true

        guard let window else {
            isTrackingThumb = false
            onEditingChanged?(false)
            needsDisplay = true
            return
        }

        while let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch nextEvent.type {
            case .leftMouseDragged:
                updateValue(with: convert(nextEvent.locationInWindow, from: nil))
            case .leftMouseUp:
                updateValue(with: convert(nextEvent.locationInWindow, from: nil))
                isTrackingThumb = false
                onEditingChanged?(false)
                needsDisplay = true
                return
            default:
                break
            }
        }

        isTrackingThumb = false
        onEditingChanged?(false)
        needsDisplay = true
    }

    private var span: Double {
        max(0.000_001, sliderBounds.upperBound - sliderBounds.lowerBound)
    }

    private var trackRect: NSRect {
        let markerAllowance = effectiveSnapMarkers.isEmpty ? 0 : markerSpacing
        let availableHeight = bounds.height - markerAllowance
        let y = effectiveSnapMarkers.isEmpty
            ? (availableHeight - trackHeight) * 0.5
            : markerSpacing + (availableHeight - trackHeight) * 0.5
        return NSRect(
            x: thumbDiameter * 0.5,
            y: y,
            width: max(1, bounds.width - thumbDiameter),
            height: trackHeight
        )
    }

    private var usableWidth: CGFloat {
        max(1, bounds.width - thumbDiameter)
    }

    private func drawThumb(centerX: CGFloat, active: Bool) {
        let rect = NSRect(
            x: centerX,
            y: (bounds.height - thumbDiameter) * 0.5,
            width: thumbDiameter,
            height: thumbDiameter
        )

        let thumbRect = rect.offsetBy(dx: -thumbDiameter * 0.5, dy: 0)
        let thumbPath = NSBezierPath(ovalIn: thumbRect)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = active ? 3 : 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.set()
        NSColor.white.setFill()
        thumbPath.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSnapMarkers() {
        let markers = effectiveSnapMarkers
        guard !markers.isEmpty else { return }

        let markerY = trackRect.minY - markerSpacing + ((trackHeight - markerDiameter) * 0.5)
        let uniqueMarkers = Dictionary(
            markers.map { (normalizedMarkerKey($0), $0) },
            uniquingKeysWith: { first, _ in first }
        ).values.sorted()

        for marker in uniqueMarkers {
            let x = xPosition(for: marker, usableWidth: usableWidth)
            let rect = NSRect(
                x: x - markerDiameter * 0.5,
                y: markerY,
                width: markerDiameter,
                height: markerDiameter
            )
            let path = NSBezierPath(ovalIn: rect)
            NSColor.secondaryLabelColor.withAlphaComponent(0.35).setFill()
            path.fill()
        }
    }

    private func normalizedMarkerKey(_ value: Double) -> Int {
        Int((value * 1000).rounded())
    }

    private var effectiveSnapMarkers: [Double] {
        if !snapMarkers.isEmpty {
            return Array(snapMarkers.sorted().dropFirst().dropLast())
        }

        guard step > 0 else { return [] }
        let count = Int(((sliderBounds.upperBound - sliderBounds.lowerBound) / step).rounded()) + 1
        guard count >= 2, count <= maxAutoMarkerCount else { return [] }
        let generated = stride(from: sliderBounds.lowerBound, through: sliderBounds.upperBound, by: step).map { $0 }
        return Array(generated.dropFirst().dropLast())
    }

    private func xPosition(for value: Double, usableWidth: CGFloat) -> CGFloat {
        let t = ((value - sliderBounds.lowerBound) / span).clamped(to: 0...1)
        return (thumbDiameter * 0.5) + CGFloat(t) * usableWidth
    }

    private func value(for point: CGPoint) -> Double {
        let clampedX = point.x.clamped(to: (thumbDiameter * 0.5)...(bounds.width - thumbDiameter * 0.5))
        let normalized = Double((clampedX - (thumbDiameter * 0.5)) / usableWidth).clamped(to: 0...1)
        let rawValue = sliderBounds.lowerBound + (normalized * span)
        return snapped(rawValue).clamped(to: sliderBounds)
    }

    private func snapped(_ value: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    private func updateValue(with point: CGPoint) {
        let newValue = value(for: point)
        guard abs(newValue - currentValue) > 0.0001 else { return }
        currentValue = newValue
        onValueChanged?(newValue)
        sendAction(action, to: target)
        needsDisplay = true
    }
}
