//
//  EffectsStudioFloatingPanels.swift
//  Hypnograph
//

import SwiftUI
import AppKit

struct FloatingEffectsStudioPanel<Content: View>: View {
    let title: String
    @Binding var x: Double
    @Binding var y: Double
    @Binding var width: Double
    @Binding var height: Double
    let containerSize: CGSize
    let minWidth: CGFloat
    let minHeight: CGFloat
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    let panelOpacity: Double
    let onFrameCommit: ((CGRect) -> Void)?
    let onInteractionBegan: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @State private var moveStartRect: CGRect?

    var body: some View {
        let rect = normalizedRect()

        VStack(spacing: 0) {
            moveHandle(rect: rect)
            content()
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: rect.width, height: rect.height)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 6)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(clampedOpacity(panelOpacity))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .simultaneousGesture(
            TapGesture().onEnded {
                onInteractionBegan?()
            }
        )
        .overlay {
            FloatingPanelInteractionOverlay(
                x: $x,
                y: $y,
                width: $width,
                height: $height,
                containerSize: containerSize,
                minWidth: minWidth,
                minHeight: minHeight,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                onInteractionBegan: onInteractionBegan
            ) { rect, committed in
                if committed {
                    onFrameCommit?(rect)
                }
            }
        }
        .offset(x: rect.minX, y: rect.minY)
    }

    @ViewBuilder
    private func moveHandle(rect: CGRect) -> some View {
        HStack {
            Spacer(minLength: 0)
            Capsule()
                .fill(Color.white.opacity(0.30))
                .frame(width: 42, height: 4)
                .padding(.vertical, 6)
            Spacer(minLength: 0)
        }
        .frame(height: 16)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if moveStartRect == nil {
                        moveStartRect = rect
                        onInteractionBegan?()
                    }
                    guard let start = moveStartRect else { return }
                    var updated = start
                    updated.origin.x = start.minX + value.translation.width
                    updated.origin.y = start.minY + value.translation.height
                    let clamped = clampedRect(updated)
                    x = Double(clamped.minX)
                    y = Double(clamped.minY)
                }
                .onEnded { _ in
                    let clamped = normalizedRect()
                    x = Double(clamped.minX)
                    y = Double(clamped.minY)
                    moveStartRect = nil
                    onFrameCommit?(clamped)
                }
        )
    }

    private func normalizedRect() -> CGRect {
        let boundedMaxWidth = max(minWidth, min(maxWidth, containerSize.width))
        let boundedMaxHeight = max(minHeight, min(maxHeight, containerSize.height))

        var w = min(max(CGFloat(width), minWidth), boundedMaxWidth)
        var h = min(max(CGFloat(height), minHeight), boundedMaxHeight)
        w = min(w, containerSize.width)
        h = min(h, containerSize.height)

        var originX = CGFloat(x)
        var originY = CGFloat(y)
        let maxX = max(0, containerSize.width - w)
        let maxY = max(0, containerSize.height - h)
        originX = min(max(originX, 0), maxX)
        originY = min(max(originY, 0), maxY)

        return CGRect(x: originX, y: originY, width: w, height: h)
    }

    private func clampedRect(_ rect: CGRect) -> CGRect {
        let current = normalizedRect()
        let w = current.width
        let h = current.height
        let maxX = max(0, containerSize.width - w)
        let maxY = max(0, containerSize.height - h)
        let x = min(max(rect.minX, 0), maxX)
        let y = min(max(rect.minY, 0), maxY)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func clampedOpacity(_ value: Double) -> Double {
        min(max(value, 0.1), 1.0)
    }
}

struct FloatingPanelInteractionOverlay: NSViewRepresentable {
    @Binding var x: Double
    @Binding var y: Double
    @Binding var width: Double
    @Binding var height: Double

    let containerSize: CGSize
    let minWidth: CGFloat
    let minHeight: CGFloat
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    let onInteractionBegan: (() -> Void)?
    let onRectChanged: (CGRect, Bool) -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.onRectUpdate = { rect, committed in
            x = Double(rect.minX)
            y = Double(rect.minY)
            width = Double(rect.width)
            height = Double(rect.height)
            onRectChanged(rect, committed)
        }
        view.onInteractionBegan = onInteractionBegan
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        nsView.modelRect = CGRect(x: x, y: y, width: width, height: height)
        nsView.containerSize = containerSize
        nsView.minWidth = minWidth
        nsView.minHeight = minHeight
        nsView.maxWidth = maxWidth
        nsView.maxHeight = maxHeight
        nsView.onInteractionBegan = onInteractionBegan
    }

    final class InteractionView: NSView {
        enum Mode {
            case left
            case right
            case top
            case bottom
            case topLeft
            case topRight
            case bottomLeft
            case bottomRight

            var hasLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
            var hasRight: Bool { self == .right || self == .topRight || self == .bottomRight }
            var hasTop: Bool { self == .top || self == .topLeft || self == .topRight }
            var hasBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
        }

        override var isFlipped: Bool { true }

        var modelRect: CGRect = .zero
        var containerSize: CGSize = .zero
        var minWidth: CGFloat = 280
        var minHeight: CGFloat = 220
        var maxWidth: CGFloat = 2000
        var maxHeight: CGFloat = 2000
        var onRectUpdate: ((CGRect, Bool) -> Void)?
        var onInteractionBegan: (() -> Void)?

        private let edgeThreshold: CGFloat = 8

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else { return nil }
            return interactionMode(at: point) == nil ? nil : self
        }

        override func resetCursorRects() {
            discardCursorRects()
            let band = edgeThreshold
            let left = NSRect(x: 0, y: band, width: band, height: max(0, bounds.height - band * 2))
            let right = NSRect(x: max(bounds.width - band, 0), y: band, width: band, height: max(0, bounds.height - band * 2))
            let top = NSRect(x: band, y: 0, width: max(0, bounds.width - band * 2), height: band)
            let bottom = NSRect(x: band, y: max(bounds.height - band, 0), width: max(0, bounds.width - band * 2), height: band)
            addCursorRect(left, cursor: .resizeLeftRight)
            addCursorRect(right, cursor: .resizeLeftRight)
            addCursorRect(top, cursor: .resizeUpDown)
            addCursorRect(bottom, cursor: .resizeUpDown)
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let localStart = convert(event.locationInWindow, from: nil)
            guard let mode = interactionMode(at: localStart) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onInteractionBegan?()
            }
            let startFrame = modelRect
            let startWindowPoint = event.locationInWindow
            var latestFrame = startFrame

            while let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) {
                switch next.type {
                case .leftMouseDragged:
                    let currentPoint = next.locationInWindow
                    let deltaX = currentPoint.x - startWindowPoint.x
                    let deltaY = startWindowPoint.y - currentPoint.y
                    latestFrame = resolvedRect(from: startFrame, mode: mode, deltaX: deltaX, deltaY: deltaY)
                    modelRect = latestFrame
                    onRectUpdate?(latestFrame, false)
                case .leftMouseUp:
                    onRectUpdate?(latestFrame, true)
                    return
                default:
                    break
                }
            }
        }

        private func interactionMode(at point: CGPoint) -> Mode? {
            let nearLeft = point.x <= edgeThreshold
            let nearRight = point.x >= bounds.width - edgeThreshold
            let nearTop = point.y <= edgeThreshold
            let nearBottom = point.y >= bounds.height - edgeThreshold

            if nearLeft && nearTop { return .topLeft }
            if nearRight && nearTop { return .topRight }
            if nearLeft && nearBottom { return .bottomLeft }
            if nearRight && nearBottom { return .bottomRight }
            if nearLeft { return .left }
            if nearRight { return .right }
            if nearTop { return .top }
            if nearBottom { return .bottom }
            return nil
        }

        private func resolvedRect(from start: CGRect, mode: Mode, deltaX: CGFloat, deltaY: CGFloat) -> CGRect {
            let boundedMaxWidth = max(minWidth, min(maxWidth, containerSize.width))
            let boundedMaxHeight = max(minHeight, min(maxHeight, containerSize.height))

            var x = start.minX
            var y = start.minY
            var w = start.width
            var h = start.height

            if mode.hasLeft {
                x += deltaX
                w -= deltaX
            }
            if mode.hasRight {
                w += deltaX
            }
            if mode.hasTop {
                y += deltaY
                h -= deltaY
            }
            if mode.hasBottom {
                h += deltaY
            }

            w = min(max(w, minWidth), boundedMaxWidth)
            h = min(max(h, minHeight), boundedMaxHeight)

            if mode.hasLeft {
                x = start.maxX - w
            }
            if mode.hasTop {
                y = start.maxY - h
            }

            let maxX = max(0, containerSize.width - w)
            let maxY = max(0, containerSize.height - h)
            x = min(max(x, 0), maxX)
            y = min(max(y, 0), maxY)

            return CGRect(x: x, y: y, width: w, height: h)
        }
    }
}
