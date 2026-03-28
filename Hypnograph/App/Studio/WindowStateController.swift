//
//  WindowStateController.swift
//  Hypnograph
//

import Foundation
import HypnoUI

@MainActor
final class WindowStateController: ObservableObject {
    @Published private(set) var windowState = WindowState()
    @Published private(set) var mainWindowFullScreen: Bool = true

    private struct PersistedWindowState: Codable {
        let windowState: WindowState
        let mainWindowFullScreen: Bool
    }

    init() {
        loadFromDisk()
    }

    var isCleanScreen: Bool {
        windowState.isCleanScreen
    }

    func registerWindow(_ windowID: String, defaultVisible: Bool = false) {
        var next = windowState
        next.register(windowID, defaultVisible: defaultVisible)
        windowState = next
    }

    func isWindowVisible(_ windowID: String) -> Bool {
        windowState.isVisible(windowID)
    }

    @discardableResult
    func toggleWindow(_ windowID: String) -> Bool {
        var next = windowState
        let consumed = next.toggle(windowID)
        windowState = next
        saveToDisk()
        return consumed
    }

    func setWindowVisible(_ windowID: String, visible: Bool) {
        var next = windowState
        next.set(windowID, visible: visible)
        windowState = next
        saveToDisk()
    }

    func toggleCleanScreen() {
        var next = windowState
        if next.isCleanScreen {
            next.isCleanScreen = false
        } else if next.hasAnyWindowVisible {
            next.isCleanScreen = true
        }
        windowState = next
        saveToDisk()
    }

    func setMainWindowFullScreen(_ isFullScreen: Bool) {
        guard mainWindowFullScreen != isFullScreen else { return }
        mainWindowFullScreen = isFullScreen
        saveToDisk()
    }

    func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let persisted = PersistedWindowState(
                windowState: windowState,
                mainWindowFullScreen: mainWindowFullScreen
            )
            let data = try encoder.encode(persisted)
            try data.write(to: windowStateFileURL)
            print("WindowStateController: Saved window state to disk")
        } catch {
            print("WindowStateController: Failed to save window state: \(error)")
        }
    }

    private var windowStateFileURL: URL {
        Environment.appSupportDirectory
            .appendingPathComponent("window-state.json")
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: windowStateFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: windowStateFileURL)
            let decoder = JSONDecoder()

            if let persisted = try? decoder.decode(PersistedWindowState.self, from: data) {
                windowState = persisted.windowState
                mainWindowFullScreen = persisted.mainWindowFullScreen
                print("WindowStateController: Loaded window state from disk")
                return
            }

            windowState = try decoder.decode(WindowState.self, from: data)
            mainWindowFullScreen = true
            print("WindowStateController: Loaded legacy window state from disk")
        } catch {
            print("WindowStateController: Failed to load window state: \(error)")
        }
    }
}
