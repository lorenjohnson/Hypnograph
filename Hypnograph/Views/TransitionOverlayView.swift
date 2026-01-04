//
//  TransitionOverlayView.swift
//  Hypnograph
//
//  Displays the captured frame during crossfade transitions.
//  Fades out as the new hypnogram loads underneath.
//

import SwiftUI
import CoreImage
import AppKit

/// Overlay view that displays a captured frame and fades out during transitions
struct TransitionOverlayView: View {
    @ObservedObject var transitionManager: TransitionManager

    var body: some View {
        if transitionManager.isTransitioning, let cgImage = transitionManager.transitionImage {
            TransitionImageView(
                cgImage: cgImage,
                opacity: transitionManager.transitionOpacity
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
}

/// NSViewRepresentable that renders a CGImage using CALayer for smooth opacity animation
struct TransitionImageView: NSViewRepresentable {
    let cgImage: CGImage
    let opacity: Double

    func makeNSView(context: Context) -> NSView {
        let view = LayerBackedImageView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let imageView = nsView as? LayerBackedImageView else { return }
        imageView.setImage(cgImage, opacity: opacity)
    }
}

/// Layer-backed NSView that renders CGImage via CALayer.contents
class LayerBackedImageView: NSView {
    private var imageLayer: CALayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let imgLayer = CALayer()
        imgLayer.contentsGravity = .resizeAspectFill
        imgLayer.masksToBounds = true
        layer?.addSublayer(imgLayer)
        imageLayer = imgLayer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer?.frame = bounds
        CATransaction.commit()
    }

    func setImage(_ cgImage: CGImage, opacity: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer?.contents = cgImage
        imageLayer?.opacity = Float(opacity)
        imageLayer?.frame = bounds
        CATransaction.commit()
    }
}
