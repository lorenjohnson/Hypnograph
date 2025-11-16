import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var viewModel: HypnogramViewModel
    @ObservedObject var renderQueue: RenderQueue

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Live multi-layer preview: selected layers + current candidate.
            MultiLayerPreviewView(
                layers: viewModel.previewLayers,
                currentLayerIndex: viewModel.currentLayerIndex,
                currentLayerTime: Binding(
                    get: { viewModel.currentCandidateStartOverride },
                    set: { viewModel.currentCandidateStartOverride = $0 }
                ),
                outputSize: viewModel.outputSize
            )
            .ignoresSafeArea()

            // HUD
            if viewModel.isHUDVisible {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hypnogram")
                        .font(.headline)
                        .padding(.bottom, 8)

                    if renderQueue.activeJobs > 0 {
                        Text("In queue: \(renderQueue.activeJobs)")
                            .font(.subheadline)
                            .padding(.bottom, 8)
                    } else {
                        Text("In queue: 0")
                            .font(.caption)
                            .padding(.bottom, 8)
                    }

                    Text("Layer \(viewModel.currentLayerIndex + 1) of \(viewModel.maxLayers)")
                        .font(.caption)

                    Text("Blend mode: \(viewModel.currentBlendModeName)")
                        .font(.caption)

                    Text("N = Next Candidate • Return = Accept Candidate • M = Blend Mode • R = Render Hypnogram • Delete = Back")
                        .font(.caption)
                        .padding(.top, 8)
                }
                .foregroundColor(.white)
                .padding()
            }
        }
    }
}
