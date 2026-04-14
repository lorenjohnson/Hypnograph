import Foundation

enum StudioPanelDescriptor: String, CaseIterable, Identifiable {
    case properties
    case newCompositions
    case effects
    case hypnograms

    var id: String { panelID }

    var panelID: String {
        switch self {
        case .properties: return "propertiesPanel"
        case .newCompositions: return "newCompositionsPanel"
        case .effects: return "effectsPanel"
        case .hypnograms: return "hypnogramsPanel"
        }
    }

    var title: String {
        switch self {
        case .properties: return "Properties"
        case .newCompositions: return "New Compositions"
        case .effects: return "Effect Chains"
        case .hypnograms: return "Hypnograms"
        }
    }

    var systemImage: String {
        switch self {
        case .properties: return "slider.horizontal.3"
        case .newCompositions: return "sparkles.rectangle.stack"
        case .effects: return "wand.and.stars"
        case .hypnograms: return "tray.full"
        }
    }

    var shortcutCharacter: Character {
        switch self {
        case .properties: return "1"
        case .newCompositions: return "2"
        case .effects: return "3"
        case .hypnograms: return "4"
        }
    }

    var shortcutLabel: String {
        "⌥\(shortcutCharacter)"
    }
}
