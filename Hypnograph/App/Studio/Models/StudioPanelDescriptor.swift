import Foundation

enum StudioPanelDescriptor: String, CaseIterable, Identifiable {
    case sequence
    case composition
    case outputSettings
    case newCompositions
    case sources
    case effects
    case hypnograms

    var id: String { panelID }

    var panelID: String {
        switch self {
        case .sequence: return "sequencePanel"
        case .composition: return "compositionPanel"
        case .outputSettings: return "outputSettingsPanel"
        case .newCompositions: return "newCompositionsPanel"
        case .sources: return "sourcesPanel"
        case .effects: return "effectsPanel"
        case .hypnograms: return "hypnogramsPanel"
        }
    }

    var title: String {
        switch self {
        case .sequence: return "Sequence"
        case .composition: return "Composition"
        case .outputSettings: return "Output Settings"
        case .newCompositions: return "New Compositions"
        case .sources: return "Sources"
        case .effects: return "Effect Chains"
        case .hypnograms: return "Hypnograms"
        }
    }

    var systemImage: String {
        switch self {
        case .sequence: return "timeline.selection"
        case .composition: return "square.on.square"
        case .outputSettings: return "slider.horizontal.3"
        case .newCompositions: return "sparkles.rectangle.stack"
        case .sources: return "photo.on.rectangle"
        case .effects: return "wand.and.stars"
        case .hypnograms: return "tray.full"
        }
    }

    var shortcutCharacter: Character {
        switch self {
        case .sequence: return "1"
        case .composition: return "2"
        case .outputSettings: return "3"
        case .newCompositions: return "4"
        case .sources: return "5"
        case .effects: return "6"
        case .hypnograms: return "7"
        }
    }

    var shortcutLabel: String {
        "⌥\(shortcutCharacter)"
    }
}
