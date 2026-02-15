import SwiftUI

struct RecordDeckBar: View {
    let isPaused: Bool
    let isRecording: Bool
    let rangeText: String
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onRecordToggle: () -> Void
    let onSaveRecording: () -> Void
    let onRenderRecording: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            deckButton(systemName: "backward.fill", label: "Prev", action: onPrevious)
            deckButton(systemName: isPaused ? "play.fill" : "pause.fill", label: isPaused ? "Play" : "Pause", action: onPlayPause)
            deckButton(systemName: "forward.fill", label: "Next", action: onNext)

            Divider()
                .frame(height: 22)

            Button(action: onRecordToggle) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isRecording ? Color.red : Color.red.opacity(0.35))
                        .frame(width: 8, height: 8)
                    Text(isRecording ? "Stop" : "Record")
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isRecording ? Color.red.opacity(0.35) : Color.white.opacity(0.08))
                )
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 22)

            Text(rangeText.uppercased())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 6)

            deckButton(systemName: "square.and.arrow.down", label: "Save", action: onSaveRecording)
            deckButton(systemName: "film.stack", label: "Render", action: onRenderRecording)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private func deckButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}
