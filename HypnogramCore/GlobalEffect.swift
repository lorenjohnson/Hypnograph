enum GlobalEffect: String, CaseIterable {
    case none
    case monochrome
    case noir
    case sepia
    case bloom
    case invert

    var ciFilterNames: [String] {
        switch self {
        case .none:
            return []
        case .monochrome:
            return ["CIColorMonochrome"]
        case .noir:
            return ["CIPhotoEffectNoir"]
        case .sepia:
            return ["CISepiaTone"]
        case .bloom:
            return ["CIBloom"]
        case .invert:
            return ["CIColorInvert"]
        }
    }
}