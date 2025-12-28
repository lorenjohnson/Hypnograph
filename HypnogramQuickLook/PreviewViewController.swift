//
//  PreviewViewController.swift
//  HypnogramQuickLook
//
//  QuickLook preview for .hypnogram files
//  Displays the embedded snapshot image and basic recipe info
//

import Cocoa
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {

    /// Image view for the snapshot
    private var imageView: NSImageView!

    /// Label for recipe info
    private var infoLabel: NSTextField!

    override var nibName: NSNib.Name? {
        return NSNib.Name("PreviewViewController")
    }

    override func loadView() {
        super.loadView()

        // Create image view
        imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        // Create info label with dark background
        infoLabel = NSTextField(labelWithString: "")
        infoLabel.font = .systemFont(ofSize: 13, weight: .medium)
        infoLabel.textColor = .white
        infoLabel.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        infoLabel.drawsBackground = true
        infoLabel.alignment = .center
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoLabel)

        // Layout constraints
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: infoLabel.topAnchor),

            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            infoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            infoLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            infoLabel.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // Load the hypnogram JSON
        let data = try Data(contentsOf: url)
        let recipe = try JSONDecoder().decode(HypnogramFile.self, from: data)

        // Extract and display snapshot
        if let snapshotBase64 = recipe.snapshot,
           let imageData = Data(base64Encoded: snapshotBase64),
           let image = NSImage(data: imageData) {
            await MainActor.run {
                imageView.image = image
            }
        }

        // Build info string
        let sourceCount = recipe.sources.count
        let duration = recipe.targetDuration.value / Int64(recipe.targetDuration.timescale)
        let effectCount = recipe.effectChain?.effects?.count ?? 0

        let infoText = "\(sourceCount) source\(sourceCount == 1 ? "" : "s") · \(duration)s · \(effectCount) effect\(effectCount == 1 ? "" : "s")"

        await MainActor.run {
            infoLabel.stringValue = infoText
        }
    }
}

// MARK: - Minimal Codable Types (subset of main app's types for the extension)

/// Minimal representation of HypnogramRecipe for QuickLook
struct HypnogramFile: Codable {
    let sources: [HypnogramSourceInfo]
    let targetDuration: CMTimeInfo
    let playRate: Float?
    let effectChain: EffectChainInfo?
    let snapshot: String?
}

/// Minimal source info - we just need to count them
struct HypnogramSourceInfo: Codable {
    // Empty - we just count the array
}

/// CMTime representation
struct CMTimeInfo: Codable {
    let value: Int64
    let timescale: Int32
}

/// Effect chain representation
struct EffectChainInfo: Codable {
    let effects: [EffectInfo]?
}

/// Single effect info
struct EffectInfo: Codable {
    let type: String
}
