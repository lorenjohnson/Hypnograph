//
//  TextOverlayEffect.swift
//  Hypnograph
//
//  Displays user-typed text with configurable font size and screen position.
//  The text can be typed live and appears immediately on screen.
//

import CoreImage
import CoreGraphics
import Foundation
import AppKit

/// Text alignment options for positioning
enum TextAlignment: String, CaseIterable {
    case center = "center"
    case top = "top"
    case bottom = "bottom"
    case left = "left"
    case right = "right"
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"
    
    var displayLabel: String {
        switch self {
        case .center: return "Center"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .right: return "Right"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

/// Displays user-typed text overlay on frames
final class TextOverlayEffect: Effect {
    
    // MARK: - Parameter Specs
    
    static var parameterSpecs: [String: ParameterSpec] {
        [
            "text": .string(default: "Hello World"),
            "fontSize": .float(default: 48.0, range: 8.0...200.0),
            "alignment": .choice(default: "center", options: TextAlignment.allCases.map { ($0.rawValue, $0.displayLabel) }),
            "textColor": .color(default: "#FFFFFF"),
            "opacity": .float(default: 1.0, range: 0.0...1.0),
            "strokeWidth": .float(default: 2.0, range: 0.0...8.0),
            "fontName": .string(default: "Menlo"),
            "marginX": .float(default: 40.0, range: 0.0...200.0),
            "marginY": .float(default: 40.0, range: 0.0...200.0)
        ]
    }
    
    // MARK: - Properties
    
    var name: String { "Text Overlay" }
    var requiredLookback: Int { 0 }
    
    var text: String
    var fontSize: Float
    var alignment: TextAlignment
    var textColor: String
    var opacity: Float
    var strokeWidth: Float
    var fontName: String
    var marginX: Float
    var marginY: Float
    
    // MARK: - Init
    
    init(text: String, fontSize: Float, alignment: TextAlignment, textColor: String,
         opacity: Float, strokeWidth: Float, fontName: String, marginX: Float, marginY: Float) {
        self.text = text
        self.fontSize = max(8, min(200, fontSize))
        self.alignment = alignment
        self.textColor = textColor
        self.opacity = max(0, min(1, opacity))
        self.strokeWidth = max(0, min(8, strokeWidth))
        self.fontName = fontName
        self.marginX = max(0, min(200, marginX))
        self.marginY = max(0, min(200, marginY))
    }
    
    required convenience init?(params: [String: AnyCodableValue]?) {
        let p = Params(params, specs: Self.parameterSpecs)
        let alignmentStr = p.string("alignment")
        let alignment = TextAlignment(rawValue: alignmentStr) ?? .center
        self.init(
            text: params?["text"]?.stringValue ?? "Hello World",
            fontSize: p.float("fontSize"),
            alignment: alignment,
            textColor: p.string("textColor"),
            opacity: p.float("opacity"),
            strokeWidth: p.float("strokeWidth"),
            fontName: params?["fontName"]?.stringValue ?? "Menlo",
            marginX: p.float("marginX"),
            marginY: p.float("marginY")
        )
    }
    
    // MARK: - Effect Protocol
    
    func apply(to image: CIImage, context: inout RenderContext) -> CIImage {
        guard !text.isEmpty else { return image }
        
        let extent = image.extent
        let width = Int(extent.width)
        let height = Int(extent.height)
        
        guard width > 0, height > 0 else { return image }
        
        // Create graphics context for text rendering
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cgContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        
        // Clear to transparent
        cgContext.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
        cgContext.setBlendMode(.copy)
        cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        cgContext.setBlendMode(.normal)
        
        // Render text
        renderText(to: cgContext, width: width, height: height)
        
        // Convert to CIImage and composite
        guard let cgImage = cgContext.makeImage() else { return image }
        let textImage = CIImage(cgImage: cgImage)
        
        return textImage.composited(over: image)
    }
    
    func reset() {
        // No temporal state to reset
    }
    
    func copy() -> Effect {
        TextOverlayEffect(text: text, fontSize: fontSize, alignment: alignment,
                         textColor: textColor, opacity: opacity, strokeWidth: strokeWidth,
                         fontName: fontName, marginX: marginX, marginY: marginY)
    }

    // MARK: - Text Rendering

    private func renderText(to context: CGContext, width: Int, height: Int) {
        let font = NSFont(name: fontName, size: CGFloat(fontSize)) ?? NSFont.systemFont(ofSize: CGFloat(fontSize))
        let color = NSColor.fromHex(textColor) ?? .white

        // Paragraph style
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping

        // Set alignment based on position
        switch alignment {
        case .left, .topLeft, .bottomLeft:
            paragraphStyle.alignment = .left
        case .right, .topRight, .bottomRight:
            paragraphStyle.alignment = .right
        case .center, .top, .bottom:
            paragraphStyle.alignment = .center
        }

        // Calculate text size
        let maxWidth = CGFloat(width) - CGFloat(marginX) * 2
        let maxHeight = CGFloat(height) - CGFloat(marginY) * 2
        let constraints = CGSize(width: maxWidth, height: maxHeight)

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        let attrString = NSAttributedString(string: text, attributes: baseAttrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attrString)
        let textSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil, constraints, nil
        )

        // Calculate position based on alignment
        let position = calculatePosition(textSize: textSize, screenWidth: CGFloat(width), screenHeight: CGFloat(height))

        // Create text rect (CoreGraphics uses bottom-left origin)
        let textRect = CGRect(x: position.x, y: position.y, width: textSize.width, height: textSize.height)
        let path = CGPath(rect: textRect, transform: nil)

        // Draw stroke first (if enabled)
        if strokeWidth > 0 {
            let strokeColor = contrastingColor(for: color).withAlphaComponent(CGFloat(opacity))
            let strokeAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: strokeColor,
                .strokeColor: strokeColor,
                .strokeWidth: CGFloat(strokeWidth),
                .paragraphStyle: paragraphStyle
            ]
            let strokeString = NSAttributedString(string: text, attributes: strokeAttrs)
            let strokeFramesetter = CTFramesetterCreateWithAttributedString(strokeString)
            let strokeFrame = CTFramesetterCreateFrame(strokeFramesetter, CFRange(location: 0, length: 0), path, nil)
            context.saveGState()
            CTFrameDraw(strokeFrame, context)
            context.restoreGState()
        }

        // Draw fill on top
        let fillAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color.withAlphaComponent(CGFloat(opacity)),
            .paragraphStyle: paragraphStyle
        ]
        let fillString = NSAttributedString(string: text, attributes: fillAttrs)
        let fillFramesetter = CTFramesetterCreateWithAttributedString(fillString)
        let fillFrame = CTFramesetterCreateFrame(fillFramesetter, CFRange(location: 0, length: 0), path, nil)
        context.saveGState()
        CTFrameDraw(fillFrame, context)
        context.restoreGState()
    }

    /// Calculate text position based on alignment (in CoreGraphics coordinates - bottom-left origin)
    private func calculatePosition(textSize: CGSize, screenWidth: CGFloat, screenHeight: CGFloat) -> CGPoint {
        let marginXCG = CGFloat(marginX)
        let marginYCG = CGFloat(marginY)

        var x: CGFloat
        var y: CGFloat

        // Calculate X position
        switch alignment {
        case .left, .topLeft, .bottomLeft:
            x = marginXCG
        case .right, .topRight, .bottomRight:
            x = screenWidth - textSize.width - marginXCG
        case .center, .top, .bottom:
            x = (screenWidth - textSize.width) / 2
        }

        // Calculate Y position (CoreGraphics: 0 = bottom, screenHeight = top)
        switch alignment {
        case .top, .topLeft, .topRight:
            y = screenHeight - textSize.height - marginYCG
        case .bottom, .bottomLeft, .bottomRight:
            y = marginYCG
        case .center, .left, .right:
            y = (screenHeight - textSize.height) / 2
        }

        return CGPoint(x: max(0, x), y: max(0, y))
    }

    /// Get a contrasting color for stroke (dark for light colors, light for dark)
    private func contrastingColor(for color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return .black }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.5 ? .black : .white
    }
}

