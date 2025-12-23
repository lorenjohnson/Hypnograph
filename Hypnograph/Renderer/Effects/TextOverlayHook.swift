//
//  TextOverlayHook.swift
//  Hypnograph
//
//  Overlays random text from files in Application Support/Hypnograph/text/
//
//  Architecture note: This effect is designed to transition to a TextSource type in the future.
//  The text selection, positioning, and timing logic are kept separable for easy extraction.
//  When that happens, this will support both random-from-disk mode and direct text input mode,
//  with the actual text sequence captured when materializing to a stored recipe.
//

import CoreImage
import CoreGraphics
import Foundation
import AppKit

// MARK: - Seeded Random Number Generator

/// A seedable random number generator for reproducible randomness.
/// Uses the same algorithm as the system RNG but with a fixed seed.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        // xorshift64* algorithm - fast and good quality for our purposes
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }
}

/// Text snippet with display properties
struct TextSnippet {
    let text: String
    var position: CGPoint
    var fontSize: CGFloat
    var opacity: Float
    var wrapExtension: CGFloat  // Fixed wrap width extension (set once at creation)
    var framesRemaining: Int
    var initialDuration: Int  // For fade in/out calculation
}

/// Overlays text loaded from text files onto frames
final class TextOverlayHook: RenderHook {

    // MARK: - Parameter Specs

    static var parameterSpecs: [String: ParameterSpec] {
        [
            "fontSize": .float(default: 32.0, range: 8.0...120.0),
            "fontSizeVariation": .float(default: 0.3, range: 0.0...1.0),  // ±30% by default
            "opacity": .float(default: 0.8, range: 0.0...1.0),
            "maxTextCount": .int(default: 3, range: 1...10),
            "changeIntervalFrames": .int(default: 90, range: 10...600),
            "durationMultiplier": .float(default: 2.0, range: 0.5...10.0)  // frames = chars * multiplier
        ]
    }

    // MARK: - Properties

    var name: String { "Text Overlay" }
    var requiredLookback: Int { 0 }

    var fontSize: Float
    var fontSizeVariation: Float
    var opacity: Float
    var maxTextCount: Int
    var changeIntervalFrames: Int
    var durationMultiplier: Float  // frames = text.count * multiplier
    var fontName: String

    /// Seed for reproducible randomness. Same seed = same text sequence, positions, timing.
    /// This enables performance display to match preview exactly.
    let randomSeed: UInt64

    // State
    private var textLines: [String] = []
    private var activeSnippets: [TextSnippet] = []
    private var framesSinceLastAdd: Int = 0
    private var lastSize: CGSize = .zero
    private var isLoading = false
    private var hasLoaded = false

    /// Seeded random number generator for reproducible behavior
    private var rng: SeededRandomNumberGenerator

    // Position history to prevent clustering (tracks last N spawn positions)
    private var recentPositions: [CGPoint] = []
    private static let maxPositionHistory = 12  // Remember last 12 positions

    // Limits to prevent slow loading
    private static let maxFiles = 100
    private static let maxFileSize = 100_000  // 100KB per file
    private static let maxTotalLines = 1000

    // MARK: - Init

    init(fontSize: Float = 32.0, fontSizeVariation: Float = 0.3, opacity: Float = 0.8,
         maxTextCount: Int = 3, changeIntervalFrames: Int = 90, durationMultiplier: Float = 2.0,
         fontName: String = "Menlo", randomSeed: UInt64? = nil) {
        self.fontSize = fontSize
        self.fontSizeVariation = fontSizeVariation
        self.opacity = opacity
        self.maxTextCount = maxTextCount
        self.changeIntervalFrames = changeIntervalFrames
        self.durationMultiplier = durationMultiplier
        self.fontName = fontName

        // Generate a new seed if not provided (first creation)
        // Copy operations pass the existing seed for reproducibility
        let seed = randomSeed ?? UInt64.random(in: 0...UInt64.max)
        self.randomSeed = seed
        self.rng = SeededRandomNumberGenerator(seed: seed)

        // Don't load here - lazy load on first use
    }

    // MARK: - Text Loading (Lazy, Async)

    /// Trigger async loading if not already loaded
    private func ensureTextLoaded() {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true

        // Load on background queue to avoid blocking main thread
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.loadTextFilesSync()
            DispatchQueue.main.async {
                self?.isLoading = false
                self?.hasLoaded = true
            }
        }
    }

    private func loadTextFilesSync() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let textDir = appSupport.appendingPathComponent("Hypnograph/text", isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: textDir, withIntermediateDirectories: true)

        // Recursively find all files (with limit)
        let allFiles = findAllFiles(in: textDir)

        if allFiles.isEmpty {
            textLines = ["No files found", "Add text files to:", textDir.path]
            return
        }

        var loadedLines: [String] = []

        // Try to read each file as text (any extension)
        for file in allFiles {
            guard loadedLines.count < Self.maxTotalLines else { break }

            if let content = readAsText(file) {
                // Split into blocks by double newlines (paragraphs)
                let blocks = content.components(separatedBy: "\n\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                if blocks.isEmpty {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        loadedLines.append(trimmed)
                    }
                } else {
                    let remaining = Self.maxTotalLines - loadedLines.count
                    loadedLines.append(contentsOf: blocks.prefix(remaining))
                }
            }
        }

        if loadedLines.isEmpty {
            loadedLines = ["No readable text found"]
        }

        // Thread-safe update
        DispatchQueue.main.async { [weak self] in
            self?.textLines = loadedLines
        }
    }

    /// Recursively find all files in a directory (with limits)
    private func findAllFiles(in directory: URL) -> [URL] {
        var files: [URL] = []
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return files
        }

        for case let fileURL as URL in enumerator {
            guard files.count < Self.maxFiles else { break }

            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if resourceValues.isRegularFile == true {
                    // Skip files that are too large
                    if let size = resourceValues.fileSize, size <= Self.maxFileSize {
                        files.append(fileURL)
                    }
                }
            } catch {
                // Skip files we can't read properties for
            }
        }
        return files
    }

    /// Try to read a file as text - handles RTF, Markdown, and plain text
    private func readAsText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        // Quick binary check: look for null bytes (common in binary files)
        if data.contains(0) {
            return nil
        }

        let ext = url.pathExtension.lowercased()

        // RTF: Use NSAttributedString to extract plain text
        if ext == "rtf" || ext == "rtfd" {
            return parseRTF(data: data)
        }

        // Get raw text content
        guard let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Markdown: Strip formatting
        if ext == "md" || ext == "markdown" {
            return parseMarkdown(content)
        }

        return content
    }

    /// Parse RTF to plain text using NSAttributedString
    private func parseRTF(data: Data) -> String? {
        // Try RTF first, then RTFD
        if let attrString = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            return attrString.string
        }

        if let attrString = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        ) {
            return attrString.string
        }

        return nil
    }

    /// Strip markdown formatting to plain text
    private func parseMarkdown(_ content: String) -> String {
        var text = content

        // Remove code blocks (``` ... ```)
        text = text.replacingOccurrences(
            of: "```[\\s\\S]*?```",
            with: "",
            options: .regularExpression
        )

        // Remove inline code (`...`)
        text = text.replacingOccurrences(
            of: "`([^`]+)`",
            with: "$1",
            options: .regularExpression
        )

        // Remove headers (# ## ### etc) - keep the text
        text = text.replacingOccurrences(
            of: "^#{1,6}\\s*",
            with: "",
            options: .regularExpression
        )

        // Remove bold/italic (**text**, *text*, __text__, _text_)
        text = text.replacingOccurrences(
            of: "[*_]{1,2}([^*_]+)[*_]{1,2}",
            with: "$1",
            options: .regularExpression
        )

        // Remove links [text](url) -> text
        text = text.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]+\\)",
            with: "$1",
            options: .regularExpression
        )

        // Remove images ![alt](url)
        text = text.replacingOccurrences(
            of: "!\\[[^\\]]*\\]\\([^)]+\\)",
            with: "",
            options: .regularExpression
        )

        // Remove horizontal rules (---, ***, ___)
        text = text.replacingOccurrences(
            of: "^[-*_]{3,}$",
            with: "",
            options: .regularExpression
        )

        // Remove blockquotes (> )
        text = text.replacingOccurrences(
            of: "^>\\s*",
            with: "",
            options: .regularExpression
        )

        // Remove list markers (- , * , 1. )
        text = text.replacingOccurrences(
            of: "^[\\-*]\\s+",
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "^\\d+\\.\\s+",
            with: "",
            options: .regularExpression
        )

        return text
    }

    private func randomLine() -> String {
        guard !textLines.isEmpty else { return "No text" }
        let index = Int.random(in: 0..<textLines.count, using: &rng)
        return textLines[index]
    }

    private func randomFontSize() -> CGFloat {
        let base = CGFloat(fontSize)
        let variation = base * CGFloat(fontSizeVariation)
        return base + CGFloat.random(in: -variation...variation, using: &rng)
    }

    /// Random opacity around the base value (±40% variation, clamped to 0.1-1.0)
    private func randomOpacity() -> Float {
        let variation: Float = 0.4  // ±40% of the base opacity
        let delta = opacity * variation
        let randomized = opacity + Float.random(in: -delta...delta, using: &rng)
        return max(0.1, min(1.0, randomized))  // Clamp to reasonable range
    }

    /// Random CGFloat in range using seeded RNG
    private func randomCGFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat.random(in: range, using: &rng)
    }

    /// Random position with spatial distribution to avoid clustering
    /// Uses rejection sampling against recent position history (not just active snippets)
    private func randomPosition(for size: CGSize) -> CGPoint {
        // Can start slightly off-screen (negative) on top/left edges
        let offscreenAmount: CGFloat = 50

        // X: from -50 to 85% of width (exclude far right where only 1 char would show)
        let minX = -offscreenAmount
        let maxX = size.width * 0.85

        // Y: from -50 to 100% of height (text wraps down, so full range is fine)
        let minY = -offscreenAmount
        let maxY = size.height

        // Minimum distance from recent positions (as fraction of screen diagonal)
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        let minDistance = diagonal * 0.20  // At least 20% of diagonal apart

        // Try to find a position that's well-separated from recent spawn points
        // Use rejection sampling with limited attempts
        for _ in 0..<30 {
            let x = randomCGFloat(in: minX...maxX)
            let y = randomCGFloat(in: minY...maxY)
            let candidate = CGPoint(x: x, y: y)

            // Check distance to all recent positions (not just active snippets)
            var tooClose = false
            for pos in recentPositions {
                let dx = candidate.x - pos.x
                let dy = candidate.y - pos.y
                let distance = sqrt(dx * dx + dy * dy)
                if distance < minDistance {
                    tooClose = true
                    break
                }
            }

            if !tooClose {
                // Record this position in history
                recordPosition(candidate)
                return candidate
            }
        }

        // Fallback: use stratified random position based on history count
        // Cycle through a 3x3 grid to ensure variety
        let gridCols = 3
        let gridRows = 3
        let cellIndex = recentPositions.count % (gridCols * gridRows)
        let col = cellIndex % gridCols
        let row = cellIndex / gridCols

        // Random position within the grid cell
        let cellWidth = (maxX - minX) / CGFloat(gridCols)
        let cellHeight = (maxY - minY) / CGFloat(gridRows)

        let cellMinX = minX + CGFloat(col) * cellWidth
        let cellMinY = minY + CGFloat(row) * cellHeight

        let x = randomCGFloat(in: cellMinX...(cellMinX + cellWidth))
        let y = randomCGFloat(in: cellMinY...(cellMinY + cellHeight))

        let position = CGPoint(x: x, y: y)
        recordPosition(position)
        return position
    }

    /// Record a spawn position in history (maintains fixed size buffer)
    private func recordPosition(_ position: CGPoint) {
        recentPositions.append(position)
        // Keep only the last N positions
        if recentPositions.count > Self.maxPositionHistory {
            recentPositions.removeFirst()
        }
    }

    // MARK: - RenderHook

    func willRenderFrame(_ context: inout RenderContext, image: CIImage) -> CIImage {
        // Trigger lazy loading on first use
        ensureTextLoaded()

        let extent = image.extent
        lastSize = extent.size

        // Update snippets - decrement duration, remove expired
        activeSnippets = activeSnippets.compactMap { snippet in
            var s = snippet
            s.framesRemaining -= 1
            return s.framesRemaining > 0 ? s : nil
        }

        // Only add snippets if we have text loaded
        guard !textLines.isEmpty else { return image }

        // Add new snippet if interval elapsed and under max
        framesSinceLastAdd += 1
        if framesSinceLastAdd >= changeIntervalFrames && activeSnippets.count < maxTextCount {
            addNewSnippet(size: extent.size)
            framesSinceLastAdd = 0
        }

        // Render text overlay
        guard !activeSnippets.isEmpty else { return image }

        return renderTextOverlay(on: image)
    }

    private func addNewSnippet(size: CGSize) {
        let text = randomLine()
        let fSize = randomFontSize()
        let snippetOpacity = randomOpacity()
        // Set wrap extension once at creation (not every frame)
        let wrapExt = randomCGFloat(in: 0...200)

        // Duration scales with text length: longer text stays longer
        // Minimum 30 frames so short text is still readable
        let baseDuration = Float(text.count) * durationMultiplier
        let duration = max(30, Int(baseDuration))

        let snippet = TextSnippet(
            text: text,
            position: randomPosition(for: size),
            fontSize: fSize,
            opacity: snippetOpacity,
            wrapExtension: wrapExt,
            framesRemaining: duration,
            initialDuration: duration
        )
        activeSnippets.append(snippet)
    }

    private func renderTextOverlay(on image: CIImage) -> CIImage {
        let extent = image.extent
        let width = Int(extent.width)
        let height = Int(extent.height)

        // Create bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
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
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw each snippet with word wrapping
        // Maximum allowed overflow beyond frame edges
        let maxOverflow: CGFloat = 50

        for snippet in activeSnippets {
            let font = NSFont(name: fontName, size: snippet.fontSize) ?? NSFont.systemFont(ofSize: snippet.fontSize)

            // Fade in/out at edges of duration (use snippet's initial duration)
            let fadeFrames = max(1, min(20, snippet.initialDuration / 4))
            let fadeIn = min(1.0, Float(snippet.initialDuration - snippet.framesRemaining) / Float(fadeFrames))
            let fadeOut = min(1.0, Float(snippet.framesRemaining) / Float(fadeFrames))
            let alpha = snippet.opacity * fadeIn * fadeOut

            // Calculate wrap width: from position to right edge + max overflow
            // This ensures text stays within frame + ~50px
            let rightEdge = CGFloat(width) + maxOverflow
            let availableWidth = rightEdge - snippet.position.x
            let wrapWidth = max(100, min(availableWidth, CGFloat(width) * 0.8))

            // Calculate max height: from position to bottom edge + max overflow
            let bottomEdge = CGFloat(height) + maxOverflow
            let maxHeight = max(100, bottomEdge - snippet.position.y)

            // Paragraph style for wrapping
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.alignment = .left

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(CGFloat(alpha)),
                .paragraphStyle: paragraphStyle
            ]

            let attrString = NSAttributedString(string: snippet.text, attributes: attrs)

            // Use CTFramesetter for multi-line text with wrapping
            let framesetter = CTFramesetterCreateWithAttributedString(attrString)

            // Calculate text size with constrained width and height
            let constraints = CGSize(width: wrapWidth, height: maxHeight)
            let textSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: 0), nil, constraints, nil
            )

            // Text rect stays within constrained bounds
            let textRect = CGRect(x: snippet.position.x, y: snippet.position.y,
                                  width: min(textSize.width, wrapWidth),
                                  height: min(textSize.height, maxHeight))
            let path = CGPath(rect: textRect, transform: nil)

            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)

            context.saveGState()
            CTFrameDraw(frame, context)
            context.restoreGState()
        }

        // Convert to CIImage and composite
        guard let cgImage = context.makeImage() else { return image }
        let textImage = CIImage(cgImage: cgImage)

        // Composite text over original
        return textImage.composited(over: image)
    }

    func reset() {
        activeSnippets.removeAll()
        recentPositions.removeAll()
        framesSinceLastAdd = 0
        // Mark as not loaded so next use will reload (picks up new files)
        hasLoaded = false
        isLoading = false
    }

    func copy() -> RenderHook {
        // Pass the same seed so the copy produces identical random sequences
        TextOverlayHook(fontSize: fontSize, fontSizeVariation: fontSizeVariation, opacity: opacity,
                        maxTextCount: maxTextCount, changeIntervalFrames: changeIntervalFrames,
                        durationMultiplier: durationMultiplier, fontName: fontName,
                        randomSeed: randomSeed)
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
