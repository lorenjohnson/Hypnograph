//
//  SessionFileActions.swift
//  Hypnograph
//
//  UI helpers for opening and saving session files.
//

import AppKit
import Foundation
import UniformTypeIdentifiers
import HypnoCore

@MainActor
enum SessionFileActions {
    static func saveAs(
        session: HypnographSession,
        snapshot: CGImage,
        onSaved: (() -> Void)? = nil
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedContentTypes()
        panel.nameFieldStringValue = SessionStore.defaultFilename()
        panel.directoryURL = SessionStore.sessionsDirectory

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if SessionStore.save(session, snapshot: snapshot, to: url) != nil {
                onSaved?()
            }
        }
    }

    static func openSession(
        onLoaded: @escaping (HypnographSession) -> Void,
        onFailure: (() -> Void)? = nil
    ) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedContentTypes()
        panel.directoryURL = SessionStore.sessionsDirectory
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let session = SessionStore.load(from: url) else {
                onFailure?()
                return
            }
            onLoaded(session)
        }
    }

    private static func allowedContentTypes() -> [UTType] {
        let types = SessionStore.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [UTType.data] : types
    }
}
