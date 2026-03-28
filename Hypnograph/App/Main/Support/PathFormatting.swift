//
//  PathFormatting.swift
//  Hypnograph
//

import Foundation

enum PathFormatting {
    static func displayPath(_ path: String) -> String {
        ((path as NSString).expandingTildeInPath as NSString).abbreviatingWithTildeInPath
    }

    static func storagePath(from url: URL) -> String {
        let expandedPath = url.path
        let homePath = NSHomeDirectory()
        if expandedPath.hasPrefix(homePath) {
            return "~" + expandedPath.dropFirst(homePath.count)
        }
        return expandedPath
    }

    static func storagePaths(from urls: [URL]) -> [String] {
        urls.map(storagePath(from:))
    }
}
