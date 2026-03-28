//
//  EffectsComposerSettings.swift
//  Hypnograph
//

import Foundation

struct EffectsComposerSettings: Codable {
    enum PersistedSourceKind: String, Codable {
        case file
        case photos
        case sample
    }

    var panelOpacity: Double
    var showCodePanel: Bool
    var showInspectorPanel: Bool
    var showManifestPanel: Bool
    var showLiveControlsPanel: Bool
    var showLogOverlay: Bool
    var lastSourceKind: PersistedSourceKind?
    var lastSourceValue: String?

    static let defaultValue = EffectsComposerSettings(
        panelOpacity: 0.72,
        showCodePanel: true,
        showInspectorPanel: true,
        showManifestPanel: false,
        showLiveControlsPanel: true,
        showLogOverlay: true,
        lastSourceKind: nil,
        lastSourceValue: nil
    )

    private enum CodingKeys: String, CodingKey {
        case panelOpacity
        case showCodePanel
        case showInspectorPanel
        case showManifestPanel
        case showLiveControlsPanel
        case showLogOverlay
        case lastSourceKind
        case lastSourceValue
    }

    init(
        panelOpacity: Double,
        showCodePanel: Bool,
        showInspectorPanel: Bool,
        showManifestPanel: Bool,
        showLiveControlsPanel: Bool,
        showLogOverlay: Bool,
        lastSourceKind: PersistedSourceKind?,
        lastSourceValue: String?
    ) {
        self.panelOpacity = panelOpacity
        self.showCodePanel = showCodePanel
        self.showInspectorPanel = showInspectorPanel
        self.showManifestPanel = showManifestPanel
        self.showLiveControlsPanel = showLiveControlsPanel
        self.showLogOverlay = showLogOverlay
        self.lastSourceKind = lastSourceKind
        self.lastSourceValue = lastSourceValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        panelOpacity = try container.decodeIfPresent(Double.self, forKey: .panelOpacity) ?? Self.defaultValue.panelOpacity
        showCodePanel = try container.decodeIfPresent(Bool.self, forKey: .showCodePanel) ?? Self.defaultValue.showCodePanel
        showInspectorPanel = try container.decodeIfPresent(Bool.self, forKey: .showInspectorPanel) ?? Self.defaultValue.showInspectorPanel
        showManifestPanel = try container.decodeIfPresent(Bool.self, forKey: .showManifestPanel) ?? Self.defaultValue.showManifestPanel
        showLiveControlsPanel = try container.decodeIfPresent(Bool.self, forKey: .showLiveControlsPanel) ?? Self.defaultValue.showLiveControlsPanel
        showLogOverlay = try container.decodeIfPresent(Bool.self, forKey: .showLogOverlay) ?? Self.defaultValue.showLogOverlay
        lastSourceKind = try container.decodeIfPresent(PersistedSourceKind.self, forKey: .lastSourceKind)
        lastSourceValue = try container.decodeIfPresent(String.self, forKey: .lastSourceValue)
    }
}
