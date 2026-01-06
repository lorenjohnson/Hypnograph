import AppKit
import Foundation

enum DivineEnvironment {
    private static let appFolderName: String = {
        if let suffix = Bundle.main.bundleIdentifier?.split(separator: ".").last {
            return String(suffix)
        }
        return "Divine"
    }()

    static var appSupportDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = base.appendingPathComponent(appFolderName, isDirectory: true)

        if !fm.fileExists(atPath: appDir.path) {
            try? fm.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        }

        return appDir
    }

    static var settingsURL: URL {
        appSupportDirectory.appendingPathComponent("divine-settings.json")
    }

    static func showSettingsFolderInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([appSupportDirectory])
    }
}
