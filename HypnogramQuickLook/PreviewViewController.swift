//
//  PreviewViewController.swift
//  HypnogramQuickLook
//
//  QuickLook preview for .hypnogram files
//  Data-based preview that renders the embedded snapshot image plus summary info
//

import Cocoa
import Quartz

/// Data-based Quick Look preview controller that renders the embedded hypnogram snapshot
/// and a short textual summary.
class PreviewViewController: NSViewController, QLPreviewingController {

    private let imageView = NSImageView()
    private let infoLabel = NSTextField(labelWithString: "")

    // MARK: - View setup

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.black.cgColor

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown

        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.alignment = .center
        infoLabel.lineBreakMode = .byTruncatingTail

        rootView.addSubview(imageView)
        rootView.addSubview(infoLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: rootView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: rootView.heightAnchor, multiplier: 0.85),

            infoLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            infoLabel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 12),
            infoLabel.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -12),
            infoLabel.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor, constant: -8)
        ])

        self.view = rootView
    }

    // MARK: - QLPreviewingController

    func preparePreviewOfFile(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        // Load and parse the hypnogram JSON on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                NSLog("HypnogramQuickLook: Loading file from \(url)")
                let data = try Data(contentsOf: url)
                NSLog("HypnogramQuickLook: Loaded \(data.count) bytes")

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw NSError(domain: "HypnogramQuickLook", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
                }

                NSLog("HypnogramQuickLook: Parsed JSON successfully")

                // Decode embedded snapshot image (base64 JPEG)
                var previewImage: NSImage? = nil
                if let snapshotBase64 = json["snapshot"] as? String,
                   let snapshotData = Data(base64Encoded: snapshotBase64) {
                    previewImage = NSImage(data: snapshotData)
                }

                // Extract source count
                let sourceCount = (json["sources"] as? [[String: Any]])?.count ?? 0

                // Extract duration
                var durationSeconds = 0
                if let targetDuration = json["targetDuration"] as? [String: Any],
                   let seconds = targetDuration["seconds"] as? Double {
                    durationSeconds = Int(seconds)
                }

                // Extract effect count
                var effectCount = 0
                if let effectChain = json["effectChain"] as? [String: Any],
                   let effects = effectChain["effects"] as? [[String: Any]] {
                    effectCount = effects.count
                }

                let infoText = "\(sourceCount) source\(sourceCount == 1 ? "" : "s") · \(durationSeconds)s · \(effectCount) effect\(effectCount == 1 ? "" : "s")"

                NSLog("HypnogramQuickLook: Preview ready - image: \(previewImage != nil), info: \(infoText)")

                DispatchQueue.main.async {
                    self.imageView.image = previewImage
                    self.infoLabel.stringValue = infoText
                    completionHandler(nil)
                }
            } catch {
                NSLog("HypnogramQuickLook: Error - \(error)")
                DispatchQueue.main.async {
                    completionHandler(error)
                }
            }
        }
    }
}
