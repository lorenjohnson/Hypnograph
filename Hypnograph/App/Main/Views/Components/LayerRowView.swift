import SwiftUI
import CoreLocation
import Photos
import HypnoCore
import AppKit

struct LayerRowView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Main
    @ObservedObject var thumbnailStore: LayerThumbnailStore

    let index: Int
    @Binding var layer: HypnogramLayer

    let isSelected: Bool
    let isExpanded: Bool
    let onSelect: () -> Void
    let onToggleExpanded: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var lastVisibleOpacity: Double = 1.0

    private var title: String {
        switch layer.mediaClip.file.source {
        case .url(let url):
            return url.lastPathComponent
        case .external(let identifier):
            return photosFilename(for: identifier) ?? "Photos Item"
        }
    }

    private var subtitle: String? {
        let base = subtitleBase()
        let blend = blendModeDisplayName(layer.blendMode, index: index)
        if let base, !base.isEmpty {
            return blend == nil ? base : "\(base) · \(blend!)"
        }
        return blend
    }

    private var isSoloActive: Bool {
        main.activePlayer.effectManager.flashSoloIndex == index
    }

    private var isMuted: Bool {
        layer.isMuted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSelected {
                        onToggleExpanded()
                    } else {
                        onSelect()
                    }
                }

            if isExpanded {
                expandedContent
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.0 : 0.5)
        )
        .onAppear {
            if layer.opacity > 0.001 {
                lastVisibleOpacity = layer.opacity
            }
            thumbnailStore.loadIfNeeded(for: layer, targetSize: CGSize(width: 56, height: 42))
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            thumbnailView

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button {
                layer.isMuted.toggle()
                main.activePlayer.notifySessionMutated()
            } label: {
                Text("M")
                    .font(.caption.weight(.bold))
                    .frame(width: 20, height: 20)
                    .background(isMuted ? Color.red : Color.clear)
                    .foregroundStyle(isMuted ? .white : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                if isSoloActive {
                    main.activePlayer.effectManager.setFlashSolo(nil)
                } else {
                    main.activePlayer.effectManager.setFlashSolo(index)
                }
            } label: {
                Text("S")
                    .font(.caption.weight(.bold))
                    .frame(width: 20, height: 20)
                    .background(isSoloActive ? Color.yellow : Color.clear)
                    .foregroundStyle(isSoloActive ? .black : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                toggleVisibility()
            } label: {
                Image(systemName: layer.opacity <= 0.001 ? "eye.slash" : "eye")
                    .font(.caption)
                    .foregroundStyle(layer.opacity <= 0.001 ? .tertiary : .primary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .contextMenu {
            Button {
                revealSource()
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .disabled(!canRevealInFinder)

            Divider()

            Button {
                onDuplicate()
            } label: {
                Label("Duplicate Layer", systemImage: "plus.square.on.square")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Layer", systemImage: "trash")
            }
        }
    }

    private var thumbnailView: some View {
        Group {
            if let image = thumbnailStore.image(for: layer) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.06))
                    Image(systemName: layer.mediaClip.file.mediaKind == .video ? "film" : "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 56, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Blend")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: {
                        if index == 0 {
                            return BlendMode.sourceOver
                        }
                        return layer.blendMode ?? BlendMode.defaultMontage
                    },
                    set: { newValue in
                        guard index != 0 else { return }
                        layer.blendMode = newValue
                        main.activePlayer.notifySessionMutated()
                    }
                )) {
                    Text("Normal").tag(BlendMode.sourceOver)
                    ForEach(BlendMode.all, id: \.self) { mode in
                        Text(blendModeName(mode))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140, alignment: .trailing)
                .disabled(index == 0)
                .opacity(index == 0 ? 0.6 : 1.0)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Opacity")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(layer.opacity.clamped(to: 0...1) * 100))%")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { layer.opacity.clamped(to: 0...1) },
                    set: { newValue in
                        layer.opacity = newValue.clamped(to: 0...1)
                        if layer.opacity > 0.001 {
                            lastVisibleOpacity = layer.opacity
                        }
                        main.activePlayer.notifySessionMutated()
                    }
                ), in: 0...1)
            }

            EffectChainView(
                state: state,
                main: main,
                layer: index,
                title: "Effects",
                isCollapsible: true
            )
        }
    }

    private func toggleVisibility() {
        if layer.opacity <= 0.001 {
            layer.opacity = lastVisibleOpacity.clamped(to: 0...1)
        } else {
            lastVisibleOpacity = layer.opacity
            layer.opacity = 0
        }
        main.activePlayer.notifySessionMutated()
    }

    private func subtitleBase() -> String? {
        switch layer.mediaClip.file.source {
        case .url(let url):
            guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) else {
                return nil
            }
            if let date = values.creationDate ?? values.contentModificationDate {
                return Self.dateFormatter.string(from: date)
            }
            return nil
        case .external(let identifier):
            guard let asset = ApplePhotos.shared.fetchAsset(localIdentifier: identifier) else { return nil }
            var parts: [String] = []
            if let date = asset.creationDate {
                parts.append(Self.dateFormatter.string(from: date))
            }
            if let location = asset.location {
                parts.append(Self.locationString(location))
            }
            return parts.joined(separator: " · ")
        }
    }

    private var canRevealInFinder: Bool {
        switch layer.mediaClip.file.source {
        case .url:
            return true
        case .external:
            return false
        }
    }

    private func revealSource() {
        switch layer.mediaClip.file.source {
        case .url(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .external:
            break
        }
    }

    private func photosFilename(for identifier: String) -> String? {
        guard let asset = ApplePhotos.shared.fetchAsset(localIdentifier: identifier) else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)

        // Prefer "primary" resource types for clearer filenames.
        if let resource = resources.first(where: { $0.type == .pairedVideo || $0.type == .video || $0.type == .photo }) {
            return resource.originalFilename
        }
        return resources.first?.originalFilename
    }

    private static func locationString(_ location: CLLocation) -> String {
        let lat = abs(location.coordinate.latitude)
        let lon = abs(location.coordinate.longitude)
        let latSuffix = location.coordinate.latitude >= 0 ? "N" : "S"
        let lonSuffix = location.coordinate.longitude >= 0 ? "E" : "W"
        return String(format: "%.2f%@, %.2f%@", lat, latSuffix, lon, lonSuffix)
    }

    private func blendModeDisplayName(_ mode: String?, index: Int) -> String? {
        if index == 0 { return nil }
        let resolved = mode ?? BlendMode.defaultMontage
        let name = blendModeName(resolved)
        return name == "Normal" ? nil : name
    }

    private func blendModeName(_ mode: String) -> String {
        if mode == BlendMode.sourceOver { return "Normal" }
        if mode == BlendMode.defaultMontage { return "Screen" }
        return blendModeNameFromCoreImageFilter(mode)
    }

    private func blendModeNameFromCoreImageFilter(_ filterName: String) -> String {
        var name = filterName
        if name.hasPrefix("CI") {
            name.removeFirst(2)
        }
        if name.hasSuffix("BlendMode") {
            name = String(name.dropLast("BlendMode".count))
        }
        if name.hasSuffix("Compositing") {
            name = String(name.dropLast("Compositing".count))
        }
        switch name {
        case "Addition": return "Add"
        case "LinearDodge": return "Linear Dodge"
        case "ColorDodge": return "Color Dodge"
        case "PinLight": return "Pin Light"
        case "SoftLight": return "Soft Light"
        case "HardLight": return "Hard Light"
        case "ColorBurn": return "Color Burn"
        default: return name
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
