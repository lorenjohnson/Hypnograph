import SwiftUI
import HypnoCore

struct SourcesPanelView: View {
    @ObservedObject var state: HypnographState
    @ObservedObject var main: Studio

    @State private var isRequestingPhotos = false
    @State private var showPhotosAlbumsPicker = false

    enum ApplePhotosAddMode: String, CaseIterable, Identifiable {
        case allItems
        case albums
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .allItems:
                return "All Items"
            case .albums:
                return "Specific Albums"
            case .custom:
                return "Custom Selection"
            }
        }
    }

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
        let hasMissingPath: Bool
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
                canEditSelection: false,
                hasMissingPath: filesystemPathsMissing(for: row.paths)
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
                    canEditSelection: false,
                    hasMissingPath: false
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
                    canEditSelection: true,
                    hasMissingPath: false
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
                    canEditSelection: false,
                    hasMissingPath: false
                )
            )
        }

        return rows
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            Text("Manage the media pool used for random clip generation, and keep source setup out of the menu bar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            sourcesSection
            mediaTypesSection
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            ApplePhotosSourcePickerSheet(
                albums: ApplePhotos.shared.fetchUserAlbums(),
                authorizationStatus: state.photosAuthorizationStatus,
                isRequestingPhotos: isRequestingPhotos,
                suppressInitialKeyboardFocus: state.appSettings.keyboardAccessibilityOverridesEnabled,
                isPresented: $showPhotosAlbumsPicker,
                onAddAllItems: {
                    Task { @MainActor in
                        await main.addApplePhotosAllSource()
                    }
                },
                onAddAlbums: { keys in
                    Task { @MainActor in
                        await main.addApplePhotosAlbumSources(keys)
                    }
                },
                onChooseCustomSelection: {
                    state.showPhotosPicker = true
                },
                onRequestAccess: {
                    requestPhotosAccess()
                },
                onOpenSystemSettings: {
                    main.openApplePhotosPrivacySettings()
                }
            )
        }
    }

    private var mediaTypesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionDivider()
            PanelSectionHeader(title: "Media Types")

            PanelInlineFieldRow(title: "Videos") {
                PanelToggleView(isOn: Binding(
                    get: { state.isMediaTypeActive(.videos) },
                    set: { _ in state.toggleMediaType(.videos) }
                ))
                .fixedSize()
            }

            PanelInlineFieldRow(title: "Images") {
                PanelToggleView(isOn: Binding(
                    get: { state.isMediaTypeActive(.images) },
                    set: { _ in state.toggleMediaType(.images) }
                ))
                .fixedSize()
            }
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionDivider()
            PanelInlineFieldRow(title: "Eligible Sources: \(state.library.assetCount)") {
                Menu {
                    Button("Files or Folders…") {
                        main.addSourceLibrariesFromPanel()
                    }

                    Button("Apple Photos…") {
                        showPhotosAlbumsPicker = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Add source selection")
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

    private func sourceRow(_ row: SourceRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.typeLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)

                    Text(row.title)
                        .font(.callout.weight(.medium))

                    if row.hasMissingPath {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red.opacity(0.9))
                            .help("One or more source paths are missing")
                    }
                }

                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)

                if row.hasMissingPath {
                    Text("Source path not found")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red.opacity(0.9))
                }

                Text(assetCountText(for: row.kind))
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
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

    private func filesystemPathsMissing(for paths: [String]) -> Bool {
        paths.contains { !FileManager.default.fileExists(atPath: $0) }
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

private struct ApplePhotosSourcePickerSheet: View {
    let albums: [ApplePhotos.AlbumInfo]
    let authorizationStatus: ApplePhotos.AuthorizationStatus
    let isRequestingPhotos: Bool
    let suppressInitialKeyboardFocus: Bool
    @Binding var isPresented: Bool
    let onAddAllItems: () -> Void
    let onAddAlbums: ([String]) -> Void
    let onChooseCustomSelection: () -> Void
    let onRequestAccess: () -> Void
    let onOpenSystemSettings: () -> Void

    @State private var mode: SourcesPanelView.ApplePhotosAddMode = .allItems
    @State private var selectedKeys: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: canChooseSources ? 12 : 9) {
            Text(canChooseSources ? "Add Apple Photos Source" : "Apple Photos Access Denied")
                .font(.headline)

            if canChooseSources {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selection")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Picker("Selection", selection: $mode) {
                            ForEach(SourcesPanelView.ApplePhotosAddMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(mode.title)
                            .font(.subheadline.weight(.semibold))

                        Group {
                            switch mode {
                            case .allItems:
                                Text("Use the entire Apple Photos library as a source.")
                                    .foregroundStyle(.secondary)

                            case .albums:
                                if albums.isEmpty {
                                    Text("No user albums found.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ScrollView {
                                        LazyVStack(alignment: .leading, spacing: 8) {
                                            ForEach(albums, id: \.libraryKey) { album in
                                                HStack(spacing: 10) {
                                                    PanelToggleView(isOn: binding(for: album.libraryKey))
                                                        .fixedSize()
                                                    Text(album.title)
                                                    Spacer()
                                                    Text("\(album.assetCount)")
                                                        .foregroundStyle(.secondary)
                                                        .monospacedDigit()
                                                }
                                            }
                                        }
                                        .padding(4)
                                    }
                                    .frame(minHeight: 180, maxHeight: 240)
                                }

                            case .custom:
                                Text("Use the native Apple Photos picker to choose a custom set of items.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                ApplePhotosAccessStatusView(
                    authorizationStatus: authorizationStatus,
                    isRequestingPhotos: isRequestingPhotos,
                    presentation: .inline,
                    showsAction: false,
                    showsStatusLine: false,
                    onRequestAccess: onRequestAccess,
                    onOpenSystemSettings: onOpenSystemSettings
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            HStack {
                if canChooseSources {
                    Button("Cancel") {
                        isPresented = false
                    }

                    Spacer()

                    Button(primaryButtonTitle) {
                        handlePrimaryAction()
                    }
                    .disabled(!canPerformPrimaryAction)
                    .buttonStyle(.borderedProminent)
                } else {
                    Spacer()

                    HStack(spacing: 10) {
                        Button("Cancel") {
                            isPresented = false
                        }

                        Button {
                            if authorizationStatus == .notDetermined {
                                onRequestAccess()
                            } else {
                                onOpenSystemSettings()
                            }
                        } label: {
                            if authorizationStatus == .notDetermined || isRequestingPhotos {
                                Text(isRequestingPhotos ? "Requesting Photos Access…" : accessButtonTitle)
                            } else {
                                Label(accessButtonTitle, systemImage: "gearshape")
                            }
                        }
                        .disabled(isRequestingPhotos)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.top, canChooseSources ? 0 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, canChooseSources ? 16 : 8)
        .padding(.bottom, canChooseSources ? 16 : 8)
        .frame(
            minWidth: canChooseSources ? 560 : 430,
            idealWidth: canChooseSources ? 620 : 460,
            maxWidth: canChooseSources ? 760 : 500,
            minHeight: canChooseSources ? 250 : 156,
            idealHeight: canChooseSources ? 320 : 166,
            maxHeight: canChooseSources ? 520 : 190
        )
        .background(
            InitialWindowFocusClearer(enabled: suppressInitialKeyboardFocus)
        )
    }

    private var canChooseSources: Bool {
        authorizationStatus.canRead
    }

    private var canPerformPrimaryAction: Bool {
        switch mode {
        case .allItems:
            return true
        case .albums:
            return !selectedKeys.isEmpty
        case .custom:
            return true
        }
    }

    private var primaryButtonTitle: String {
        switch mode {
        case .custom:
            return "Choose Custom Selection…"
        case .allItems, .albums:
            return "Add Source"
        }
    }

    private func handlePrimaryAction() {
        switch mode {
        case .allItems:
            onAddAllItems()
            isPresented = false
        case .albums:
            onAddAlbums(Array(selectedKeys))
            isPresented = false
        case .custom:
            isPresented = false
            onChooseCustomSelection()
        }
    }

    private var accessButtonTitle: String {
        authorizationStatus == .notDetermined ? "Request Photos Access" : "Open System Settings"
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

private struct InitialWindowFocusClearer: NSViewRepresentable {
    let enabled: Bool

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard enabled else { return }
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nil)
        }
    }
}
