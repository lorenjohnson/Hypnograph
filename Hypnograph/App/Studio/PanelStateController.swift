//
//  PanelStateController.swift
//  Hypnograph
//

import Foundation
import HypnoUI

typealias PanelVisibilityState = WindowState

@MainActor
final class PanelStateController: ObservableObject {
    @Published private(set) var panelVisibilityState = PanelVisibilityState()
    @Published private(set) var mainWindowFullScreen: Bool = true
    @Published private(set) var panelsHidden: Bool = false
    private var panelFrames: [String: CGRect] = [:]
    private var panelOrder: [String] = []

    private static let panelIDAliases: [String: String] = [
        "hypnogramList": "hypnogramsPanel",
        "sourcesWindow": "sourcesPanel",
        "newClipsWindow": "newCompositionsPanel",
        "outputSettingsWindow": "outputSettingsPanel",
        "compositionWindow": "compositionPanel",
        "effectsWindow": "effectsPanel",
        "playerControlsWindow": "playerControlsPanel",
        "livePreview": "livePreviewPanel",
        "hud": "hudPanel"
    ]

    private struct PersistedPanelFrame: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(rect: CGRect) {
            x = rect.origin.x
            y = rect.origin.y
            width = rect.size.width
            height = rect.size.height
        }

        var rect: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }
    }

    private struct PersistedPanelState: Codable {
        let panelState: PanelVisibilityState
        let mainWindowFullScreen: Bool
        let panelFrames: [String: PersistedPanelFrame]?
        let panelOrder: [String]?
        let activePanelWindowID: String?

        private enum CodingKeys: String, CodingKey {
            case panelState
            case windowState
            case mainWindowFullScreen
            case panelFrames
            case panelOrder
            case activePanelWindowID
        }

        init(
            panelState: PanelVisibilityState,
            mainWindowFullScreen: Bool,
            panelFrames: [String: PersistedPanelFrame]?,
            panelOrder: [String]?,
            activePanelWindowID: String?
        ) {
            self.panelState = panelState
            self.mainWindowFullScreen = mainWindowFullScreen
            self.panelFrames = panelFrames
            self.panelOrder = panelOrder
            self.activePanelWindowID = activePanelWindowID
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let decodedPanelState = try? container.decode(PanelVisibilityState.self, forKey: .panelState) {
                panelState = decodedPanelState
            } else {
                panelState = try container.decode(PanelVisibilityState.self, forKey: .windowState)
            }
            mainWindowFullScreen = try container.decode(Bool.self, forKey: .mainWindowFullScreen)
            panelFrames = try container.decodeIfPresent([String: PersistedPanelFrame].self, forKey: .panelFrames)
            panelOrder = try container.decodeIfPresent([String].self, forKey: .panelOrder)
            activePanelWindowID = try container.decodeIfPresent(String.self, forKey: .activePanelWindowID)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(panelState, forKey: .panelState)
            try container.encode(mainWindowFullScreen, forKey: .mainWindowFullScreen)
            try container.encodeIfPresent(panelFrames, forKey: .panelFrames)
            try container.encodeIfPresent(panelOrder, forKey: .panelOrder)
            try container.encodeIfPresent(activePanelWindowID, forKey: .activePanelWindowID)
        }
    }

    init() {
        loadFromDisk()
    }

    func registerPanel(_ panelID: String, defaultVisible: Bool = false) {
        var next = panelVisibilityState
        next.register(panelID, defaultVisible: defaultVisible)
        panelVisibilityState = next
    }

    func isPanelVisible(_ panelID: String) -> Bool {
        panelVisibilityState.isVisible(panelID)
    }

    @discardableResult
    func togglePanel(_ panelID: String) -> Bool {
        var next = panelVisibilityState
        let consumed = next.toggle(panelID)
        panelVisibilityState = next
        saveToDisk()
        return consumed
    }

    func setPanelVisible(_ panelID: String, visible: Bool) {
        var next = panelVisibilityState
        next.set(panelID, visible: visible)
        panelVisibilityState = next
        saveToDisk()
    }

    func setMainWindowFullScreen(_ isFullScreen: Bool) {
        guard mainWindowFullScreen != isFullScreen else { return }
        mainWindowFullScreen = isFullScreen
        saveToDisk()
    }

    func setPanelsHidden(_ hidden: Bool) {
        guard panelsHidden != hidden else { return }
        panelsHidden = hidden
    }

    func panelFrame(_ panelID: String) -> CGRect? {
        panelFrames[panelID]
    }

    func panelOrderIDs() -> [String] {
        panelOrder
    }

    func setPanelOrder(_ panelIDs: [String]) {
        guard panelOrder != panelIDs else { return }
        panelOrder = panelIDs
        saveToDisk()
    }

    func setPanelFrame(_ frame: CGRect, for panelID: String) {
        guard panelFrames[panelID] != frame else { return }
        panelFrames[panelID] = frame
        saveToDisk()
    }

    func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let persisted = PersistedPanelState(
                panelState: panelVisibilityState,
                mainWindowFullScreen: mainWindowFullScreen,
                panelFrames: panelFrames.mapValues(PersistedPanelFrame.init(rect:)),
                panelOrder: panelOrder,
                activePanelWindowID: nil
            )
            let data = try encoder.encode(persisted)
            try data.write(to: stateFileURL)
            print("PanelStateController: Saved panel state to disk")
        } catch {
            print("PanelStateController: Failed to save panel state: \(error)")
        }
    }

    private var stateFileURL: URL {
        Environment.defaultPanelStateURL
    }

    private var legacyStateFileURL: URL {
        Environment.legacyDefaultPanelStateURL
    }

    private func loadFromDisk() {
        let fm = FileManager.default
        let sourceURL: URL
        if fm.fileExists(atPath: stateFileURL.path) {
            sourceURL = stateFileURL
        } else if fm.fileExists(atPath: legacyStateFileURL.path) {
            sourceURL = legacyStateFileURL
        } else {
            return
        }

        do {
            let data = try Data(contentsOf: sourceURL)
            let decoder = JSONDecoder()

            if let persisted = try? decoder.decode(PersistedPanelState.self, from: data) {
                panelVisibilityState = migratedPanelVisibilityState(from: persisted.panelState)
                mainWindowFullScreen = persisted.mainWindowFullScreen
                panelFrames = migratePanelFrameKeys(persisted.panelFrames?.mapValues(\.rect) ?? [:])
                panelOrder = migratePanelOrderIDs(persisted.panelOrder ?? persisted.activePanelWindowID.map { [$0] } ?? [])
                print("PanelStateController: Loaded panel state from disk")
                return
            }

            var loadedPanelState = try decoder.decode(PanelVisibilityState.self, from: data)
            loadedPanelState.isCleanScreen = false
            panelVisibilityState = migratedPanelVisibilityState(from: loadedPanelState)
            mainWindowFullScreen = true
            panelFrames = [:]
            panelOrder = []
            print("PanelStateController: Loaded legacy panel state from disk")
        } catch {
            print("PanelStateController: Failed to load panel state: \(error)")
        }
    }

    private func migratedPanelVisibilityState(from loadedState: PanelVisibilityState) -> PanelVisibilityState {
        var migratedState = PanelVisibilityState()
        let knownPanelIDs = [
            "hypnogramsPanel",
            "sourcesPanel",
            "newCompositionsPanel",
            "outputSettingsPanel",
            "compositionPanel",
            "effectsPanel",
            "playerControlsPanel",
            "livePreviewPanel",
            "hudPanel"
        ]

        for panelID in knownPanelIDs {
            migratedState.register(panelID, defaultVisible: false)
            if loadedState.isVisible(panelID) {
                migratedState.set(panelID, visible: true)
                continue
            }
            if let legacyID = Self.panelIDAliases.first(where: { $0.value == panelID })?.key,
               loadedState.isVisible(legacyID) {
                migratedState.set(panelID, visible: true)
            }
        }

        migratedState.isCleanScreen = false
        return migratedState
    }

    private func migratePanelFrameKeys(_ frames: [String: CGRect]) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: frames.map { key, value in
            (Self.panelIDAliases[key] ?? key, value)
        })
    }

    private func migratePanelOrderIDs(_ ids: [String]) -> [String] {
        ids.map { Self.panelIDAliases[$0] ?? $0 }
    }
}
