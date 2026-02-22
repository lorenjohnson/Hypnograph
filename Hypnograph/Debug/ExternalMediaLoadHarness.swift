import Foundation
import AVFoundation
import HypnoCore

/// Drives external-media loading UX and debug simulation scenarios.
/// Wraps HypnoCore external resolvers so UI can observe loading/downloading/failure states.
final class ExternalMediaLoadHarness: ObservableObject {
    static let shared = ExternalMediaLoadHarness()
    private static let liveIndicatorDelayNanoseconds: UInt64 = 2_000_000_000

    private enum SimulationMode {
        case live
        case slow
        case progress
        case timeout
        case failure

        var displayName: String {
            switch self {
            case .live: return "Normal"
            case .slow: return "Slow"
            case .progress: return "Download"
            case .timeout: return "Timeout"
            case .failure: return "Failure"
            }
        }
    }

    private struct RequestPlan {
        let mode: SimulationMode
        let showInitialStatus: Bool
        let detailOverride: String?
    }

    enum Scenario: String, CaseIterable, Identifiable {
        case live = "live"
        case simulateSlow = "simulate_slow"
        case simulateProgress = "simulate_progress"
        case simulateTimeout = "simulate_timeout"
        case simulateFailure = "simulate_failure"
        case sequenceFailureSlowNormalFailureNormal = "sequence_failure_slow_normal_failure_normal"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .live: return "Live (No Simulation)"
            case .simulateSlow: return "Simulate Slow Load"
            case .simulateProgress: return "Simulate Download Progress"
            case .simulateTimeout: return "Simulate Timeout"
            case .simulateFailure: return "Simulate Failure"
            case .sequenceFailureSlowNormalFailureNormal:
                return "Sequence: Fail -> Slow -> Normal -> Fail -> Normal"
            }
        }
    }

    enum Phase: Equatable {
        case loading
        case downloading
        case timeout
        case failed
    }

    struct Status: Equatable {
        let phase: Phase
        let title: String
        let detail: String?
        let progress: Double?
    }

    @Published var scenario: Scenario = .live
    @Published private(set) var status: Status?

    private var isInstalled = false
    private var statusToken: UInt64 = 0
    private var clearTask: Task<Void, Never>?
    private var activeRequestTokens: Set<UInt64> = []
    private var activeSequenceScenario: Scenario?
    private var activeSequenceIndex = 0

    private init() {}

    func installHookWrappersIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true

        let baseVideoResolver = HypnoCoreHooks.shared.resolveExternalVideo
        let baseImageResolver = HypnoCoreHooks.shared.resolveExternalImage

        HypnoCoreHooks.shared.resolveExternalVideo = { [weak self] identifier in
            guard let self else { return await baseVideoResolver?(identifier) }
            return await self.resolve(
                mediaLabel: "Photos Video",
                identifier: identifier,
                resolver: baseVideoResolver
            )
        }

        HypnoCoreHooks.shared.resolveExternalImage = { [weak self] identifier in
            guard let self else { return await baseImageResolver?(identifier) }
            return await self.resolve(
                mediaLabel: "Photos Image",
                identifier: identifier,
                resolver: baseImageResolver
            )
        }
    }

    private func resolve<T>(
        mediaLabel: String,
        identifier: String,
        resolver: ((String) async -> T?)?
    ) async -> T? {
        guard let resolver else { return nil }

        let activeScenario = await MainActor.run { scenario }
        let requestPlan = await buildRequestPlan(for: activeScenario)
        let token = await beginRequest(
            mediaLabel: mediaLabel,
            identifier: identifier,
            scenario: activeScenario,
            showInitialStatus: requestPlan.showInitialStatus,
            detailOverride: requestPlan.detailOverride
        )

        var delayedLiveLoadingTask: Task<Void, Never>?
        if requestPlan.mode == .live {
            delayedLiveLoadingTask = Task { [weak self] in
                // In production/live mode, avoid flashing the badge for normal local loads.
                // Only surface the indicator when resolution is meaningfully delayed.
                do {
                    try await Task.sleep(nanoseconds: Self.liveIndicatorDelayNanoseconds)
                } catch {
                    return
                }
                await self?.showLiveLoadingIfNeeded(
                    token: token,
                    mediaLabel: mediaLabel,
                    identifier: identifier
                )
            }
        }

        let result: T?
        switch requestPlan.mode {
        case .live:
            result = await resolver(identifier)

        case .slow:
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            result = await resolver(identifier)

        case .progress:
            await updateDownloadProgress(token: token, mediaLabel: mediaLabel, progress: 0.0)
            for step in 1...8 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                await updateDownloadProgress(
                    token: token,
                    mediaLabel: mediaLabel,
                    progress: Double(step) / 10.0
                )
            }
            let loaded = await resolver(identifier)
            if loaded != nil {
                await updateDownloadProgress(token: token, mediaLabel: mediaLabel, progress: 1.0)
            }
            result = loaded

        case .timeout:
            await updateDownloadProgress(token: token, mediaLabel: mediaLabel, progress: 0.0)
            for step in 1...8 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                await updateDownloadProgress(
                    token: token,
                    mediaLabel: mediaLabel,
                    progress: Double(step) / 10.0
                )
            }
            result = nil

        case .failure:
            try? await Task.sleep(nanoseconds: 800_000_000)
            result = nil
        }

        delayedLiveLoadingTask?.cancel()

        if result != nil {
            await clearStatusIfCurrent(token: token)
            return result
        }

        switch requestPlan.mode {
        case .timeout:
            await showTerminalStatusAndClear(
                token: token,
                phase: .timeout,
                title: "\(mediaLabel) Timed Out",
                detail: "Simulated timeout while waiting for iCloud download."
            )
        case .failure:
            await showTerminalStatusAndClear(
                token: token,
                phase: .failed,
                title: "\(mediaLabel) Failed",
                detail: "Simulated load failure."
            )
        default:
            await showTerminalStatusAndClear(
                token: token,
                phase: .failed,
                title: "\(mediaLabel) Failed",
                detail: "Could not load selected asset."
            )
        }

        return nil
    }

    private func beginRequest(
        mediaLabel: String,
        identifier: String,
        scenario: Scenario,
        showInitialStatus: Bool,
        detailOverride: String?
    ) async -> UInt64 {
        await MainActor.run {
            clearTask?.cancel()
            statusToken &+= 1
            activeRequestTokens.insert(statusToken)

            guard showInitialStatus else {
                status = nil
                return statusToken
            }

            let detail: String = detailOverride ?? {
                switch scenario {
                case .live:
                    return "Resolving \(identifier.prefix(10))..."
                case .simulateSlow:
                    return "Scenario: Simulated slow load."
                case .simulateProgress:
                    return "Scenario: Simulated iCloud download."
                case .simulateTimeout:
                    return "Scenario: Simulated timeout."
                case .simulateFailure:
                    return "Scenario: Simulated failure."
                case .sequenceFailureSlowNormalFailureNormal:
                    return "Scenario sequence active."
                }
            }()

            status = Status(
                phase: .loading,
                title: "Loading \(mediaLabel)...",
                detail: detail,
                progress: nil
            )

            return statusToken
        }
    }

    private func buildRequestPlan(for scenario: Scenario) async -> RequestPlan {
        await MainActor.run {
            if activeSequenceScenario != scenario {
                activeSequenceScenario = scenario
                activeSequenceIndex = 0
            }

            switch scenario {
            case .live:
                return RequestPlan(
                    mode: .live,
                    showInitialStatus: false,
                    detailOverride: nil
                )
            case .simulateSlow:
                return RequestPlan(
                    mode: .slow,
                    showInitialStatus: true,
                    detailOverride: nil
                )
            case .simulateProgress:
                return RequestPlan(
                    mode: .progress,
                    showInitialStatus: true,
                    detailOverride: nil
                )
            case .simulateTimeout:
                return RequestPlan(
                    mode: .timeout,
                    showInitialStatus: true,
                    detailOverride: nil
                )
            case .simulateFailure:
                return RequestPlan(
                    mode: .failure,
                    showInitialStatus: true,
                    detailOverride: nil
                )
            case .sequenceFailureSlowNormalFailureNormal:
                let sequence: [SimulationMode] = [.failure, .slow, .live, .failure, .live]
                let stepIndex = activeSequenceIndex % sequence.count
                let step = sequence[stepIndex]
                activeSequenceIndex += 1

                return RequestPlan(
                    mode: step,
                    showInitialStatus: true,
                    detailOverride: "Scenario sequence step \(stepIndex + 1)/\(sequence.count): \(step.displayName)."
                )
            }
        }
    }

    private func showLiveLoadingIfNeeded(
        token: UInt64,
        mediaLabel: String,
        identifier: String
    ) async {
        await MainActor.run {
            guard token == statusToken else { return }
            guard activeRequestTokens.contains(token) else { return }
            guard status == nil else { return }

            status = Status(
                phase: .loading,
                title: "Loading \(mediaLabel)...",
                detail: "Resolving \(identifier.prefix(10))...",
                progress: nil
            )
        }
    }

    private func updateDownloadProgress(
        token: UInt64,
        mediaLabel: String,
        progress: Double
    ) async {
        await MainActor.run {
            guard token == statusToken else { return }
            status = Status(
                phase: .downloading,
                title: "Downloading \(mediaLabel)...",
                detail: "Waiting for iCloud asset.",
                progress: min(max(progress, 0), 1)
            )
        }
    }

    private func clearStatusIfCurrent(token: UInt64) async {
        await MainActor.run {
            guard token == statusToken else { return }
            clearTask?.cancel()
            activeRequestTokens.remove(token)
            status = nil
        }
    }

    private func showTerminalStatusAndClear(
        token: UInt64,
        phase: Phase,
        title: String,
        detail: String
    ) async {
        await MainActor.run {
            guard token == statusToken else { return }
            activeRequestTokens.remove(token)
            status = Status(
                phase: phase,
                title: title,
                detail: detail,
                progress: nil
            )
            clearTask?.cancel()
            clearTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    guard token == self.statusToken else { return }
                    self.status = nil
                }
            }
        }
    }
}
