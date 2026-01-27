import SwiftUI

/// A simple double-thumb range slider for macOS SwiftUI.
/// Designed to match the Sidebar UI Redesign mockups (Liquid Glass style).
struct RangeSliderView: View {
    @Binding var range: ClosedRange<Double>
    let bounds: ClosedRange<Double>

    var step: Double = 1.0
    var minimumDistance: Double = 0.0

    @State private var activeThumb: Thumb? = nil

    private enum Thumb {
        case lower
        case upper
    }

    private var span: Double { max(0.000_001, bounds.upperBound - bounds.lowerBound) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumbDiameter: CGFloat = 16
            let trackHeight: CGFloat = 4
            let usableWidth = max(1, width - thumbDiameter)

            let lowerT = ((range.lowerBound - bounds.lowerBound) / span).clamped(to: 0...1)
            let upperT = ((range.upperBound - bounds.lowerBound) / span).clamped(to: 0...1)

            let lowerX = CGFloat(lowerT) * usableWidth
            let upperX = CGFloat(upperT) * usableWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: trackHeight)
                    .offset(y: (thumbDiameter - trackHeight) / 2)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(
                        width: max(thumbDiameter, (upperX - lowerX) + thumbDiameter),
                        height: trackHeight
                    )
                    .offset(x: lowerX, y: (thumbDiameter - trackHeight) / 2)

                thumb(x: lowerX, thumb: .lower, diameter: thumbDiameter, usableWidth: usableWidth)
                    .zIndex(activeThumb == .lower ? 2 : 1)

                thumb(x: upperX, thumb: .upper, diameter: thumbDiameter, usableWidth: usableWidth)
                    .zIndex(activeThumb == .upper ? 2 : 1)
            }
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Range Slider")
    }

    @ViewBuilder
    private func thumb(x: CGFloat, thumb: Thumb, diameter: CGFloat, usableWidth: CGFloat) -> some View {
        Circle()
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            .frame(width: diameter, height: diameter)
            .offset(x: x, y: 0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        activeThumb = thumb
                        let proposedT = (value.location.x / usableWidth).clamped(to: 0...1)
                        let proposedValue = bounds.lowerBound + Double(proposedT) * span
                        updateRange(for: thumb, proposedValue: proposedValue)
                    }
                    .onEnded { _ in
                        activeThumb = nil
                    }
            )
    }

    private func updateRange(for thumb: Thumb, proposedValue: Double) {
        let stepped = proposedValue.rounded(toNearest: step).clamped(to: bounds)

        switch thumb {
        case .lower:
            let maxLower = (range.upperBound - minimumDistance).clamped(to: bounds)
            let newLower = min(stepped, maxLower)
            let newUpper = max(range.upperBound, newLower + minimumDistance).clamped(to: bounds)
            range = newLower...newUpper
        case .upper:
            let minUpper = (range.lowerBound + minimumDistance).clamped(to: bounds)
            let newUpper = max(stepped, minUpper)
            let newLower = min(range.lowerBound, newUpper - minimumDistance).clamped(to: bounds)
            range = newLower...newUpper
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
