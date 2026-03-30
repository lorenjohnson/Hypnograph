import SwiftUI
import HypnoCore

struct SourcesWindowView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio

    @State private var isRequestingPhotos = false
    @State private var showPhotosAlbumsPicker = false

    private struct FilesystemSourceRow: Identifiable {
        let key: String
        let displayName: String
        let paths: [String]
        let assetCount: Int

        var id: String { key }
    }

    private struct SourceRow: Identifiable {
        enum Kind {
            case filesystem(paths: [String], assetCount: Int)
            case photosAll(assetCount: Int)
            case photosCustom(assetCount: Int)
            case photosAlbum(assetCount: Int)
        }

        let id: String
        let key: String
        let typeLabel: String
        let title: String
        let detail: String
        let kind: Kind
        let canEditSelection: Bool
    }

    private var folderAssetCounts: [String: Int] {
        Dictionary(uniqueKeysWithValues: state.availableLibraries.map { ($0.id, $0.assetCount) })
    }

    private var filesystemSourceRows: [FilesystemSourceRow] {
        state.settings.sourceLibraryOrder.compactMap { key in
            guard let paths = state.settings.sourceLibraries[key] else { return nil }

            let displayName: String
            if key == "default", let firstPath = paths.first {
                displayName = URL(fileURLWithPath: (firstPath as NSString).expandingTildeInPath).lastPathComponent
            } else {
                displayName = key
            }

            return FilesystemSourceRow(
                key: key,
                displayName: displayName,
                paths: paths,
                assetCount: folderAssetCounts[key] ?? 0
            )
        }
    }

    private var photosLibraries: [SourceLibraryInfo] {
        state.availableLibraries.filter { $0.type == .applePhotos }
    }

    private var photosLibrariesByID: [String: SourceLibraryInfo] {
        photosLibraries.reduce(into: [String: SourceLibraryInfo]()) { result, item in
            result[item.id] = item
        }
    }

    private var canReadPhotos: Bool {
        state.photosAuthorizationStatus.canRead
    }

    private var sourceRows: [SourceRow] {
        var rows: [SourceRow] = filesystemSourceRows.map { row in
            SourceRow(
                id: row.key,
                key: row.key,
                typeLabel: filesystemTypeLabel(for: row.paths),
                title: row.displayName,
                detail: filesystemDetail(for: row.paths),
                kind: .filesystem(paths: row.paths, assetCount: row.assetCount),
                canEditSelection: false
            )
        }

        let activeKeys = state.activeLibraryKeys

        if activeKeys.contains(ApplePhotosLibraryKeys.photosAll) {
            rows.append(
                SourceRow(
                    id: ApplePhotosLibraryKeys.photosAll,
                    key: ApplePhotosLibraryKeys.photosAll,
                    typeLabel: "Photos",
                    title: "All Items",
                    detail: "Entire Apple Photos library",
                    kind: .photosAll(assetCount: photosLibrariesByID[ApplePhotosLibraryKeys.photosAll]?.assetCount ?? 0),
                    canEditSelection: false
                )
            )
        }

        if activeKeys.contains(ApplePhotosLibraryKeys.photosCustom) || !state.customPhotosAssetIds.isEmpty {
            let count = state.customPhotosAssetIds.count
            let detail = count > 0 ? "\(count) selected items" : "Custom selection"
            rows.append(
                SourceRow(
                    id: ApplePhotosLibraryKeys.photosCustom,
                    key: ApplePhotosLibraryKeys.photosCustom,
                    typeLabel: "Photos",
                    title: "Custom Selection",
                    detail: detail,
                    kind: .photosCustom(assetCount: count),
                    canEditSelection: true
                )
            )
        }

        let activeAlbumKeys = activeKeys
            .filter { $0.hasPrefix(ApplePhotosLibraryKeys.photosPrefix) }
            .filter { $0 != ApplePhotosLibraryKeys.photosAll && $0 != ApplePhotosLibraryKeys.photosCustom }
            .sorted {
                let lhsName = photosLibrariesByID[$0]?.name ?? $0
                let rhsName = photosLibrariesByID[$1]?.name ?? $1
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }

        for key in activeAlbumKeys {
            let info = photosLibrariesByID[key]
            rows.append(
                SourceRow(
                    id: key,
                    key: key,
                    typeLabel: "Album",
                    title: info?.name ?? "Album",
                    detail: "Apple Photos album",
                    kind: .photosAlbum(assetCount: info?.assetCount ?? 0),
                    canEditSelection: false
                )
            )
        }

        return rows
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("Manage the media pool used for random clip generation, and keep source setup out of the menu bar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                mediaTypesSection
                sourcesSection
                photosAccessSection
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            Color.black.opacity(0.96)
                .ignoresSafeArea()
        )
        .onAppear {
            Task { @MainActor in
                let status = main.refreshPhotosStatus()
                if status.canRead {
                    await state.refreshPhotosLibrariesAfterAuthorization()
                } else {
                    await state.refreshAvailableLibraries()
                }
            }
        }
        .sheet(isPresented: $showPhotosAlbumsPicker) {
            ApplePhotosAlbumPickerSheet(
                albums: ApplePhotos.shared.fetchUserAlbums(),
                isPresented: $showPhotosAlbumsPicker,
                onConfirm: { keys in
                    Task { @MainActor in
                        await main.addApplePhotosAlbumSources(keys)
                    }
                }
            )
        }
    }

    private var mediaTypesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionDivider()
            sectionTitle("Media Types")

            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text("Images")
                    PanelToggleView(isOn: Binding(
                        get: { state.isMediaTypeActive(.images) },
                        set: { _ in state.toggleMediaType(.images) }
                    ))
                    .fixedSize()
                }

                HStack(spacing: 8) {
                    Text("Videos")
                    PanelToggleView(isOn: Binding(
                        get: { state.isMediaTypeActive(.videos) },
                        set: { _ in state.toggleMediaType(.videos) }
                    ))
                    .fixedSize()
                }
            }

            Text("Current eligible pool: \(state.library.assetCount) item\(state.library.assetCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionDivider()
            HStack(alignment: .center, spacing: 8) {
                sectionTitle("Source Selections")
                Spacer(minLength: 8)

                Menu {
                    Button("Files or Folders…") {
                        main.addSourceLibrariesFromPanel()
                    }

                    if canReadPhotos {
                        Divider()

                        Menu("Apple Photos") {
                            Button("All Items") {
                                Task { @MainActor in
                                    await main.addApplePhotosAllSource()
                                }
                            }

                            Button("Custom Selection…") {
                                state.showPhotosPicker = true
                            }

                            Button("Albums…") {
                                showPhotosAlbumsPicker = true
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help(canReadPhotos ? "Add source selection" : "Add files or folders")
            }

            if sourceRows.isEmpty {
                emptyState("No source selections configured yet.")
            } else {
                ForEach(sourceRows) { row in
                    sourceRow(row)
                }
            }
        }
    }

    private var photosAccessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionDivider()
            sectionTitle("Apple Photos")

            if canReadPhotos {
                Text("Apple Photos access is enabled. Add All Items, a Custom Selection, or Albums from the source menu above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple Photos access is not enabled.")
                        .foregroundStyle(.secondary)

                    Button(isRequestingPhotos ? "Requesting Photos Access…" : "Request Photos Access") {
                        requestPhotosAccess()
                    }
                    .disabled(isRequestingPhotos)
                }
            }
        }
    }

    private func sourceRow(_ row: SourceRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(row.typeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(row.title)
                        .font(.body.weight(.medium))
                }

                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Text(assetCountText(for: row.kind))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                if row.canEditSelection {
                    Button {
                        state.showPhotosPicker = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit custom selection")
                }

                Button(role: .destructive) {
                    removeSourceRow(row)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove source selection")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func filesystemTypeLabel(for paths: [String]) -> String {
        guard paths.count == 1, let firstPath = paths.first else { return "Selection" }

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: firstPath, isDirectory: &isDirectory)
        return isDirectory.boolValue ? "Folder" : "File"
    }

    private func filesystemDetail(for paths: [String]) -> String {
        if paths.count > 1 {
            return "\(paths.count) paths"
        }
        return paths.first ?? ""
    }

    private func assetCountText(for kind: SourceRow.Kind) -> String {
        let count: Int
        switch kind {
        case let .filesystem(_, assetCount),
             let .photosAll(assetCount),
             let .photosCustom(assetCount),
             let .photosAlbum(assetCount):
            count = assetCount
        }

        return "\(count) eligible item\(count == 1 ? "" : "s")"
    }

    private func removeSourceRow(_ row: SourceRow) {
        switch row.kind {
        case .filesystem:
            main.removeFolderLibrary(row.key)
        case .photosAll, .photosCustom, .photosAlbum:
            Task { @MainActor in
                await main.removePhotosSource(row.key)
            }
        }
    }

    private func requestPhotosAccess() {
        isRequestingPhotos = true
        Task { @MainActor in
            _ = await main.requestPhotosAccess()
            isRequestingPhotos = false
        }
    }

    @ViewBuilder
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func sectionDivider() -> some View {
        GlassDivider()
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
            )
    }
}

private struct ApplePhotosAlbumPickerSheet: View {
    let albums: [ApplePhotos.AlbumInfo]
    @Binding var isPresented: Bool
    let onConfirm: ([String]) -> Void

    @State private var selectedKeys: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Apple Photos Albums")
                .font(.headline)

            if albums.isEmpty {
                Text("No user albums found")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(albums, id: \.libraryKey) { album in
                            HStack(spacing: 10) {
                                Text(album.title)
                                Spacer()
                                Text("\(album.assetCount)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                PanelToggleView(isOn: binding(for: album.libraryKey))
                                    .fixedSize()
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(minHeight: 260)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }

                Spacer()

                Button("Add") {
                    onConfirm(Array(selectedKeys))
                    isPresented = false
                }
                .disabled(selectedKeys.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 760, minHeight: 360, idealHeight: 420, maxHeight: 700)
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { selectedKeys.contains(key) },
            set: { enabled in
                if enabled {
                    selectedKeys.insert(key)
                } else {
                    selectedKeys.remove(key)
                }
            }
        )
    }
}
