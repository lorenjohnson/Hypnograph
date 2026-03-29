import SwiftUI
import AppKit

/// AppKit-backed double-thumb range slider.
/// Using an NSControl here keeps drag handling reliable inside panels that
/// allow dragging the window by background clicks.
struct RangeSliderView: NSViewRepresentable {
    @Binding var range: ClosedRange<Double>
    let bounds: ClosedRange<Double>

    var step: Double = 1.0
    var minimumDistance: Double = 0.0

    @SwiftUI.Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> RangeSliderControl {
        let control = RangeSliderControl()
        control.onRangeChanged = { newRange in
            range = newRange
        }
        return control
    }

    func updateNSView(_ nsView: RangeSliderControl, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.sliderBounds = bounds
        nsView.step = step
        nsView.minimumDistance = minimumDistance
        nsView.onRangeChanged = { newRange in
            range = newRange
        }
        nsView.setRange(range)
    }
}

final class RangeSliderControl: NSControl {
    enum Thumb {
        case lower
        case upper
    }

    var sliderBounds: ClosedRange<Double> = 0...1 {
        didSet { needsDisplay = true }
    }

    var step: Double = 1.0 {
        didSet { needsDisplay = true }
    }

    var minimumDistance: Double = 0.0 {
        didSet { needsDisplay = true }
    }

    var onRangeChanged: ((ClosedRange<Double>) -> Void)?

    private(set) var range: ClosedRange<Double> = 0...1
    private var activeThumb: Thumb?
    private var dragStartPoint: CGPoint?
    private var dragStartRange: ClosedRange<Double>?

    private let thumbDiameter: CGFloat = 16
    private let thumbHitDiameter: CGFloat = 28
    private let trackHeight: CGFloat = 4

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 20)
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    func setRange(_ newRange: ClosedRange<Double>) {
        guard range != newRange else { return }
        range = newRange
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = self.trackRect
        let usableWidth = self.usableWidth

        let lowerCenterX = xPosition(for: range.lowerBound, usableWidth: usableWidth)
        let upperCenterX = xPosition(for: range.upperBound, usableWidth: usableWidth)

        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        NSColor.secondaryLabelColor.withAlphaComponent(0.3).setFill()
        trackPath.fill()

        let selectionRect = NSRect(
            x: lowerCenterX,
            y: trackRect.minY,
            width: max(thumbDiameter, upperCenterX - lowerCenterX),
            height: trackRect.height
        )
        let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        NSColor.controlAccentColor.setFill()
        selectionPath.fill()

        drawThumb(centerX: lowerCenterX, active: activeThumb == .lower)
        drawThumb(centerX: upperCenterX, active: activeThumb == .upper)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        guard let thumb = thumb(at: point) else {
            return
        }

        activeThumb = thumb
        dragStartPoint = point
        dragStartRange = range
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled,
              let activeThumb,
              let dragStartPoint,
              let dragStartRange
        else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let deltaX = point.x - dragStartPoint.x
        let deltaValue = Double(deltaX / usableWidth) * span
        let updatedRange = adjustedRange(
            from: dragStartRange,
            thumb: activeThumb,
            deltaValue: deltaValue
        )

        if updatedRange != range {
            range = updatedRange
            onRangeChanged?(updatedRange)
            sendAction(action, to: target)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        activeThumb = nil
        dragStartPoint = nil
        dragStartRange = nil
        needsDisplay = true
    }

    private var span: Double {
        max(0.000_001, sliderBounds.upperBound - sliderBounds.lowerBound)
    }

    private var trackRect: NSRect {
        let y = (bounds.height - trackHeight) * 0.5
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

    private func thumb(at point: CGPoint) -> Thumb? {
        let lowerCenter = CGPoint(
            x: xPosition(for: range.lowerBound, usableWidth: usableWidth),
            y: bounds.midY
        )
        let upperCenter = CGPoint(
            x: xPosition(for: range.upperBound, usableWidth: usableWidth),
            y: bounds.midY
        )

        let hitRadius = thumbHitDiameter * 0.5
        let lowerDistance = hypot(point.x - lowerCenter.x, point.y - lowerCenter.y)
        let upperDistance = hypot(point.x - upperCenter.x, point.y - upperCenter.y)

        let hitsLower = lowerDistance <= hitRadius
        let hitsUpper = upperDistance <= hitRadius

        switch (hitsLower, hitsUpper) {
        case (true, true):
            return lowerDistance <= upperDistance ? .lower : .upper
        case (true, false):
            return .lower
        case (false, true):
            return .upper
        case (false, false):
            return nil
        }
    }

    private func xPosition(for value: Double, usableWidth: CGFloat) -> CGFloat {
        let t = ((value - sliderBounds.lowerBound) / span).clamped(to: 0...1)
        return (thumbDiameter * 0.5) + CGFloat(t) * usableWidth
    }

    private func adjustedRange(
        from startRange: ClosedRange<Double>,
        thumb: Thumb,
        deltaValue: Double
    ) -> ClosedRange<Double> {
        let proposedValue: Double

        switch thumb {
        case .lower:
            proposedValue = startRange.lowerBound + deltaValue
        case .upper:
            proposedValue = startRange.upperBound + deltaValue
        }

        let stepped = proposedValue.rounded(toNearest: step).clamped(to: sliderBounds)

        switch thumb {
        case .lower:
            let maxLower = (startRange.upperBound - minimumDistance).clamped(to: sliderBounds)
            let newLower = min(stepped, maxLower)
            let newUpper = max(startRange.upperBound, newLower + minimumDistance).clamped(to: sliderBounds)
            return newLower...newUpper
        case .upper:
            let minUpper = (startRange.lowerBound + minimumDistance).clamped(to: sliderBounds)
            let newUpper = max(stepped, minUpper)
            let newLower = min(startRange.lowerBound, newUpper - minimumDistance).clamped(to: sliderBounds)
            return newLower...newUpper
        }
    }
}

private extension Double {
    func rounded(toNearest step: Double) -> Double {
        guard step > 0 else { return self }
        return (self / step).rounded() * step
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
