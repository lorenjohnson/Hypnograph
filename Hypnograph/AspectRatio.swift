//
//  AspectRatio.swift
//  Hypnograph
//
//  Represents an aspect ratio for output sizing.
//

import CoreGraphics

// MARK: - AspectRatio

/// Represents an aspect ratio (width / height).
/// Can be parsed from decimal (2.35) or ratio string ("16:9").
/// nil represents "fill screen" (use view's native aspect ratio).
struct AspectRatio: Codable, Equatable, CustomStringConvertible {
    /// The ratio as width / height (e.g., 16:9 = 1.778)
    let value: CGFloat
    
    /// Original string representation for display
    let displayString: String
    
    // MARK: - Common Presets
    
    static let ratio16x9 = AspectRatio(value: 16.0 / 9.0, displayString: "16:9")
    static let ratio4x3 = AspectRatio(value: 4.0 / 3.0, displayString: "4:3")
    static let ratio21x9 = AspectRatio(value: 21.0 / 9.0, displayString: "21:9")
    static let ratio1x1 = AspectRatio(value: 1.0, displayString: "1:1")
    static let ratio9x16 = AspectRatio(value: 9.0 / 16.0, displayString: "9:16")  // Portrait
    static let ratio235 = AspectRatio(value: 2.35, displayString: "2.35:1")  // Cinemascope
    static let ratio185 = AspectRatio(value: 1.85, displayString: "1.85:1")  // Theatrical
    
    static let presets: [AspectRatio] = [
        .ratio16x9, .ratio4x3, .ratio21x9, .ratio1x1, .ratio9x16, .ratio235, .ratio185
    ]
    
    // MARK: - Initialization
    
    init(value: CGFloat, displayString: String) {
        self.value = value
        self.displayString = displayString
    }
    
    /// Parse from a string like "16:9", "2.35", or "2.35:1"
    static func parse(_ string: String) -> AspectRatio? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        
        // Try ratio format (e.g., "16:9", "2.35:1")
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":")
            guard parts.count == 2,
                  let width = Double(parts[0]),
                  let height = Double(parts[1]),
                  height > 0 else {
                return nil
            }
            return AspectRatio(value: CGFloat(width / height), displayString: trimmed)
        }
        
        // Try decimal format (e.g., "2.35", "1.778")
        if let decimal = Double(trimmed), decimal > 0 {
            return AspectRatio(value: CGFloat(decimal), displayString: trimmed)
        }
        
        return nil
    }
    
    // MARK: - Size Calculation
    
    /// Calculate output size for this aspect ratio to fit within a container.
    /// The result will be the largest size with this aspect ratio that fits in the container.
    func size(fitting containerSize: CGSize) -> CGSize {
        let containerAspect = containerSize.width / containerSize.height

        if value > containerAspect {
            // Wider than container - fit to width, letterbox top/bottom
            let width = containerSize.width
            let height = width / value
            return CGSize(width: width, height: height)
        } else {
            // Taller than container - fit to height, pillarbox left/right
            let height = containerSize.height
            let width = height * value
            return CGSize(width: width, height: height)
        }
    }
    
    // MARK: - Codable
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        
        guard let parsed = AspectRatio.parse(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid aspect ratio format: \(string)"
            )
        }
        
        self.value = parsed.value
        self.displayString = parsed.displayString
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(displayString)
    }
    
    // MARK: - CustomStringConvertible

    var description: String { displayString }

    // MARK: - Size Calculation

    /// Calculate output size for this aspect ratio constrained by maxDimension.
    /// maxDimension constrains height for landscape, width for portrait.
    func size(maxDimension: Int) -> CGSize {
        let maxDim = CGFloat(maxDimension)

        if value >= 1.0 {
            // Landscape or square - height is the constraining dimension
            let height = maxDim
            let width = round(height * value)
            return CGSize(width: width, height: height)
        } else {
            // Portrait - width is the constraining dimension
            let width = maxDim
            let height = round(width / value)
            return CGSize(width: width, height: height)
        }
    }
}
