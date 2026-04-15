import Foundation
import AVFoundation
import HypnoCore

actor MediaFrameRateProbe {
    static let shared = MediaFrameRateProbe()

    private enum CacheEntry {
        case pending(Task<Double?, Never>)
        case resolved(Double?)
    }

    private var cache: [String: CacheEntry] = [:]

    func frameRate(for file: MediaFile) async -> Double? {
        guard file.mediaKind == .video else { return nil }

        let cacheKey = "\(file.source.identifier)|\(file.mediaKind.rawValue)"
        if let cached = cache[cacheKey] {
            switch cached {
            case .pending(let task):
                return await task.value
            case .resolved(let value):
                return value
            }
        }

        let task = Task<Double?, Never> {
            await Self.loadFrameRate(for: file)
        }
        cache[cacheKey] = .pending(task)
        let value = await task.value
        cache[cacheKey] = .resolved(value)
        return value
    }

    private static func loadFrameRate(for file: MediaFile) async -> Double? {
        guard let asset = await file.loadAsset() else { return nil }
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }

        let nominal = Double(track.nominalFrameRate)
        if nominal.isFinite, nominal > 0 {
            return nominal
        }

        let minFrameDuration = track.minFrameDuration
        if minFrameDuration.isValid,
           minFrameDuration.isNumeric,
           minFrameDuration.seconds > 0 {
            let derived = 1.0 / minFrameDuration.seconds
            if derived.isFinite, derived > 0 {
                return derived
            }
        }

        return nil
    }
}

enum FrameRateDisplay {
    static func text(_ fps: Double?) -> String? {
        guard let fps, fps.isFinite, fps > 0 else { return nil }

        let rounded = fps.rounded()
        if abs(fps - rounded) < 0.05 {
            return "\(Int(rounded)) fps"
        }

        return String(format: "%.2f fps", fps)
    }
}
