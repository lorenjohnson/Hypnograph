import Foundation
import AVFoundation
import HypnoCore

/// Drives external-media download UX and debug simulation scenarios.
/// Wraps HypnoCore external resolvers so UI can observe per-asset transfer state.
final class ExternalMediaLoadHarness: ObservableObject {
    static let shared = ExternalMediaLoadHarness()

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

    struct AssetDownloadStatus: Identifiable, Equatable {
        let id: String
        let localIdentifier: String
        let mediaLabel: String
        let progress: Double
    }

    private struct PendingDownloadPromotion {
        let localIdentifier: String
        let mediaLabel: String
        var latestProgress: Double
        let task: Task<Void, Never>
    }

    @Published var scenario: Scenario = .live
    @Published private(set) var activeDownloads: [AssetDownloadStatus] = []

    private var isInstalled = false
    private var activeSequenceScenario: Scenario?
    private var activeSequenceIndex = 0
    private var pendingDownloadPromotions: [String: PendingDownloadPromotion] = [:]

    private static let downloadVisibilityDelayNanoseconds: UInt64 = 700_000_000

    private init() {}

    func installHookWrappersIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true

        ApplePhotos.shared.onTransferEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleTransferEvent(event)
            }
        }

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

        let requestPlan = await buildRequestPlan(for: await MainActor.run { scenario })
        let simulatedRequestID = "simulated-\(UUID().uuidString)"

        switch requestPlan.mode {
        case .live:
            return await resolver(identifier)

        case .slow:
            for progress in [0.08, 0.14, 0.2, 0.28, 0.34] {
                await emitTransferEvent(
                    .downloading(progress: progress),
                    requestID: simulatedRequestID,
                    localIdentifier: identifier,
                    mediaLabel: mediaLabel
                )
                try? await Task.sleep(nanoseconds: 400_000_000)
            }

            let result = await resolver(identifier)
            await emitTransferEvent(
                result == nil ? .failed : .completed,
                requestID: simulatedRequestID,
                localIdentifier: identifier,
                mediaLabel: mediaLabel
            )
            return result

        case .progress:
            await emitTransferEvent(
                .downloading(progress: 0.0),
                requestID: simulatedRequestID,
                localIdentifier: identifier,
                mediaLabel: mediaLabel
            )

            for step in 1...8 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                await emitTransferEvent(
                    .downloading(progress: Double(step) / 10.0),
                    requestID: simulatedRequestID,
                    localIdentifier: identifier,
                    mediaLabel: mediaLabel
                )
            }

            let result = await resolver(identifier)
            if result != nil {
                await emitTransferEvent(
                    .downloading(progress: 1.0),
                    requestID: simulatedRequestID,
                    localIdentifier: identifier,
                    mediaLabel: mediaLabel
                )
            }
            await emitTransferEvent(
                result == nil ? .failed : .completed,
                requestID: simulatedRequestID,
                localIdentifier: identifier,
                mediaLabel: mediaLabel
            )
            return result

        case .timeout:
            await emitTransferEvent(
                .downloading(progress: 0.0),
                requestID: simulatedRequestID,
                localIdentifier: identifier,
                mediaLabel: mediaLabel
            )

            for step in 1...8 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                await emitTransferEvent(
                    .downloading(progress: Double(step) / 10.0),
                    requestID: simulatedRequestID,
                    localIdentifier: identifier,
                    mediaLabel: mediaLabel
                )
            }

            await emitTransferEvent(
                .failed,
                requestID: simulatedRequestID,
                localIdentifier: identifier,
                mediaLabel: mediaLabel
            )
            return nil

        case .failure:
            try? await Task.sleep(nanoseconds: 800_000_000)
            return nil
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
                return RequestPlan(mode: .live)
            case .simulateSlow:
                return RequestPlan(mode: .slow)
            case .simulateProgress:
                return RequestPlan(mode: .progress)
            case .simulateTimeout:
                return RequestPlan(mode: .timeout)
            case .simulateFailure:
                return RequestPlan(mode: .failure)
            case .sequenceFailureSlowNormalFailureNormal:
                let sequence: [SimulationMode] = [.failure, .slow, .live, .failure, .live]
                let stepIndex = activeSequenceIndex % sequence.count
                let step = sequence[stepIndex]
                activeSequenceIndex += 1
                return RequestPlan(mode: step)
            }
        }
    }

    private func emitTransferEvent(
        _ phase: ApplePhotos.TransferEvent.Phase,
        requestID: String,
        localIdentifier: String,
        mediaLabel: String
    ) async {
        await MainActor.run {
            handleTransferEvent(
                ApplePhotos.TransferEvent(
                    requestID: requestID,
                    localIdentifier: localIdentifier,
                    mediaLabel: mediaLabel,
                    phase: phase
                )
            )
        }
    }

    @MainActor
    private func handleTransferEvent(_ event: ApplePhotos.TransferEvent) {
        switch event.phase {
        case .downloading(let progress):
            let clamped = min(max(progress, 0), 1)
            if let index = activeDownloads.firstIndex(where: { $0.id == event.requestID }) {
                activeDownloads[index] = AssetDownloadStatus(
                    id: event.requestID,
                    localIdentifier: event.localIdentifier,
                    mediaLabel: event.mediaLabel,
                    progress: clamped
                )
            } else if var pending = pendingDownloadPromotions[event.requestID] {
                pending.latestProgress = clamped
                pendingDownloadPromotions[event.requestID] = pending
            } else {
                let requestID = event.requestID
                let promotionTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: Self.downloadVisibilityDelayNanoseconds)
                    await MainActor.run {
                        guard let self,
                              let pending = self.pendingDownloadPromotions.removeValue(forKey: requestID) else {
                            return
                        }

                        self.activeDownloads.append(
                            AssetDownloadStatus(
                                id: requestID,
                                localIdentifier: pending.localIdentifier,
                                mediaLabel: pending.mediaLabel,
                                progress: pending.latestProgress
                            )
                        )
                    }
                }

                pendingDownloadPromotions[requestID] = PendingDownloadPromotion(
                    localIdentifier: event.localIdentifier,
                    mediaLabel: event.mediaLabel,
                    latestProgress: clamped,
                    task: promotionTask
                )
            }

        case .completed, .failed:
            if let pending = pendingDownloadPromotions.removeValue(forKey: event.requestID) {
                pending.task.cancel()
            }
            activeDownloads.removeAll { $0.id == event.requestID }
        }
    }
}
