//
//  HypnogramFileActions.swift
//  Hypnograph
//
//  UI helpers for opening and saving hypnogram files.
//

import AppKit
import Foundation
import UniformTypeIdentifiers
import HypnoCore

@MainActor
enum HypnogramFileActions {
    static func saveAs(
        hypnogram: Hypnogram,
        snapshot: CGImage,
        onSaved: (() -> Void)? = nil
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedContentTypes()
        panel.nameFieldStringValue = HypnogramFileStore.defaultFilename()
        panel.directoryURL = HypnogramFileStore.hypnogramsDirectory

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if HypnogramFileStore.save(hypnogram, snapshot: snapshot, to: url) != nil {
                onSaved?()
            }
        }
    }

    static func openHypnogram(
        onLoaded: @escaping (Hypnogram) -> Void,
        onFailure: (() -> Void)? = nil
    ) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedContentTypes()
        panel.directoryURL = HypnogramFileStore.hypnogramsDirectory
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let hypnogram = HypnogramFileStore.load(from: url) else {
                onFailure?()
                return
            }
            onLoaded(hypnogram)
        }
    }

    private static func allowedContentTypes() -> [UTType] {
        let types = HypnogramFileStore.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [UTType.data] : types
    }
}
