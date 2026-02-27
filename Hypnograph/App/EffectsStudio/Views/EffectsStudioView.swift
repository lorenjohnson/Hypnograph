//
//  EffectsStudioView.swift
//  Hypnograph
//
//  Runtime effect authoring studio (v1).
//  Authoring format: effect.json + shader.metal
//

import SwiftUI
import AppKit

struct EffectsStudioView: View {
    private enum EffectsStudioPanelID: String, CaseIterable, Identifiable {
        case code
        case parameters
        case manifest
        var id: String { rawValue }
    }

    private struct EffectsStudioCleanScreenSnapshot {
        let showCodePanel: Bool
        let showInspectorPanel: Bool
        let showManifestPanel: Bool
        let showLiveControlsPanel: Bool
        let showLogOverlay: Bool
        let showChrome: Bool
    }

    @ObservedObject var state: HypnographState
    @ObservedObject var settingsStore: EffectsStudioSettingsStore
    @StateObject private var model: EffectsStudioViewModel
    @StateObject private var panelWindows = EffectsStudioPanelWindowController()
    @StateObject private var tabMonitor = EffectsStudioTabKeyMonitor()

    @State private var showPhotosPicker = false
    @State private var selectedPhotosIdentifier: String?

    @State private var autoCompile = true
    @State private var compileGeneration = 0
    @State private var didInitialLoad = false
    @State private var didLoadEffectsStudioUIState = false
    @State private var isApplyingStoredEffectsStudioUIState = false

    @State private var panelOpacity: Double = EffectsStudioSettings.defaultValue.panelOpacity
    @State private var showCodePanel = EffectsStudioSettings.defaultValue.showCodePanel
    @State private var showInspectorPanel = EffectsStudioSettings.defaultValue.showInspectorPanel
    @State private var showManifestPanel = EffectsStudioSettings.defaultValue.showManifestPanel
    @State private var showLiveControlsPanel = EffectsStudioSettings.defaultValue.showLiveControlsPanel
    @State private var showLogOverlay = EffectsStudioSettings.defaultValue.showLogOverlay

    @State private var codePanelX: Double = 20
    @State private var codePanelY: Double = 20
    @State private var codePanelW: Double = 720
    @State private var codePanelH: Double = 520

    @State private var inspectorPanelX: Double = 780
    @State private var inspectorPanelY: Double = 20
    @State private var inspectorPanelW: Double = 390
    @State private var inspectorPanelH: Double = 520
    @State private var manifestPanelX: Double = 860
    @State private var manifestPanelY: Double = 140
    @State private var manifestPanelW: Double = 420
    @State private var manifestPanelH: Double = 420
    @State private var panelStack: [EffectsStudioPanelID] = [.code, .parameters, .manifest]
    @State private var showEffectsStudioChrome = true
    @State private var cleanScreenSnapshot: EffectsStudioCleanScreenSnapshot?

    init(state: HypnographState, settingsStore: EffectsStudioSettingsStore) {
        self.state = state
        self.settingsStore = settingsStore
        _model = StateObject(wrappedValue: EffectsStudioViewModel(settingsStore: settingsStore))
    }

    var body: some View {
        VStack(spacing: 10) {
            if showEffectsStudioChrome {
                topBar
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .zIndex(10)
            }

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    previewBackdrop
                    Color.black.opacity(0.20)

                    if showLogOverlay {
                        logOverlay(
                            maxWidth: max(260, proxy.size.width * 0.46),
                            maxHeight: max(120, proxy.size.height - 20)
                        )
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
            }
            .zIndex(1)

            if showEffectsStudioChrome {
                bottomTransportBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .zIndex(10)
            }
        }
        .frame(minWidth: 1240, minHeight: 820)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if !didLoadEffectsStudioUIState {
                applyEffectsStudioUIState(settingsStore.value)
                didLoadEffectsStudioUIState = true
            }
            tabMonitor.start(
                shouldHandleEvent: shouldHandleEffectsStudioTab(event:),
                onTabPressed: toggleEffectsStudioCleanScreen
            )
            guard !didInitialLoad else { return }
            didInitialLoad = true
            model.refreshRuntimeEffectList()
            if !model.selectedRuntimeType.isEmpty {
                model.loadRuntimeEffectAsset()
            }
            model.restoreInitialSource(
                from: state.library,
                preferredLength: max(2.0, state.settings.clipLengthMaxSeconds)
            )
        }
        .onChange(of: model.selectedRuntimeType) { _, newType in
            guard didInitialLoad, !newType.isEmpty else { return }
            model.loadRuntimeEffectAsset()
        }
        .onChange(of: model.sourceCode) { _, _ in queueAutoCompile() }
        .onChange(of: model.parameters) { _, _ in queueAutoCompile() }
        .onChange(of: panelOpacity) { _, _ in persistEffectsStudioUIState() }
        .onChange(of: showCodePanel) { _, _ in persistEffectsStudioUIState() }
        .onChange(of: showInspectorPanel) { _, _ in persistEffectsStudioUIState() }
        .onChange(of: showManifestPanel) { _, _ in persistEffectsStudioUIState() }
        .onChange(of: showLiveControlsPanel) { _, _ in persistEffectsStudioUIState() }
        .onChange(of: showLogOverlay) { _, _ in persistEffectsStudioUIState() }
        .task(id: compileGeneration) {
            guard autoCompile else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            _ = model.compileCode()
        }
        .background(
            EffectsStudioPanelHostBridge(
                controller: panelWindows,
                showCodePanel: showCodePanel,
                showInspectorPanel: showInspectorPanel,
                showManifestPanel: showManifestPanel,
                showLiveControlsPanel: showLiveControlsPanel,
                panelOpacity: panelOpacity,
                codeContent: AnyView(panelWindowSurface { codePanelContent }),
                inspectorContent: AnyView(panelWindowSurface { inspectorPanelContent }),
                manifestContent: AnyView(panelWindowSurface { manifestPanelContent }),
                liveControlsContent: AnyView(panelWindowSurface { liveControlsPanelContent })
            )
            .frame(width: 0, height: 0)
        )
        .onDisappear {
            cleanScreenSnapshot = nil
            persistEffectsStudioUIState()
            tabMonitor.stop()
            panelWindows.teardown()
        }
        .sheet(isPresented: $showPhotosPicker) {
            PhotosPickerSheet(
                isPresented: $showPhotosPicker,
                preselectedIdentifiers: selectedPhotosIdentifier.map { [$0] } ?? [],
                selectionLimit: 1
            ) { identifiers in
                guard let id = identifiers.first else { return }
                selectedPhotosIdentifier = id
                model.loadPhotosSource(identifier: id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .effectsStudioToggleCleanScreen)) { _ in
            toggleEffectsStudioCleanScreen()
        }
    }

    private func panelWindowSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func panelOverlay(totalWidth: CGFloat, totalHeight: CGFloat) -> some View {
        let canvas = CGSize(width: max(100, totalWidth - 24), height: max(100, totalHeight - 24))

        ZStack(alignment: .topLeading) {
            if showCodePanel {
                FloatingEffectsStudioPanel(
                    title: "Code",
                    x: $codePanelX,
                    y: $codePanelY,
                    width: $codePanelW,
                    height: $codePanelH,
                    containerSize: canvas,
                    minWidth: 380,
                    minHeight: 260,
                    maxWidth: max(380, canvas.width),
                    maxHeight: max(260, canvas.height),
                    panelOpacity: panelOpacity,
                    onFrameCommit: persistCodePanelFrame,
                    onInteractionBegan: { bringPanelToFront(.code) }
                ) {
                    codePanelContent
                }
                .zIndex(zIndex(for: .code))
            }

            if showInspectorPanel {
                FloatingEffectsStudioPanel(
                    title: "Parameters",
                    x: $inspectorPanelX,
                    y: $inspectorPanelY,
                    width: $inspectorPanelW,
                    height: $inspectorPanelH,
                    containerSize: canvas,
                    minWidth: 300,
                    minHeight: 260,
                    maxWidth: min(max(300, canvas.width), 620),
                    maxHeight: max(260, canvas.height),
                    panelOpacity: panelOpacity,
                    onFrameCommit: persistInspectorPanelFrame,
                    onInteractionBegan: { bringPanelToFront(.parameters) }
                ) {
                    inspectorPanelContent
                }
                .zIndex(zIndex(for: .parameters))
            }
        }
        .padding(12)
    }

    private var previewBackdrop: some View {
        GeometryReader { proxy in
            if let image = model.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.10, blue: 0.16),
                        Color(red: 0.03, green: 0.04, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var topBar: some View {
        panelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Picker("", selection: $model.selectedRuntimeType) {
                        if model.runtimeEffects.isEmpty {
                            Text("No runtime effects").tag("")
                        } else {
                            Text("Draft (unsaved)").tag("")
                            ForEach(model.runtimeEffects) { effect in
                                Text(effect.displayName).tag(effect.type)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 260)
                    .disabled(model.runtimeEffects.isEmpty)

                    Button("Refresh") { model.refreshRuntimeEffectList() }
                        .buttonStyle(.bordered)

                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 2)

                    Text("Name")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Effect Name", text: $model.runtimeEffectName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 170, idealWidth: 250, maxWidth: 300)

                    Text("Version")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("1.0.0", text: $model.runtimeEffectVersion)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)

                    Button("Save") { model.saveRuntimeEffectAsset() }
                        .buttonStyle(.borderedProminent)
                    Button(role: .destructive) { model.deleteRuntimeEffectAsset() } label: {
                        Text("Delete")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    Button("New") { model.resetToTemplate() }
                        .buttonStyle(.bordered)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    panelToggleButton("Code", isOn: $showCodePanel)
                    panelToggleButton("Parameters", isOn: $showInspectorPanel)
                    panelToggleButton("Live Controls", isOn: $showLiveControlsPanel)
                    panelToggleButton("Log", isOn: $showLogOverlay)
                    panelToggleButton("Manifest", isOn: $showManifestPanel)

                    Text("Panels")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $panelOpacity, in: 0.22...0.92)
                        .frame(width: 110)
                        .help("Adjust overlay window transparency.")

                    Spacer(minLength: 0)

                    Toggle("Live", isOn: $autoCompile)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("Automatically compile after code or parameter edits.")

                    Button("Compile") { _ = model.compileCode() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private func panelToggleButton(_ title: String, isOn: Binding<Bool>) -> some View {
        if isOn.wrappedValue {
            Button(title) {
                isOn.wrappedValue.toggle()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button(title) {
                isOn.wrappedValue.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func bindingForParameter(id: UUID) -> Binding<EffectsStudioParameterDraft>? {
        guard let index = model.parameters.firstIndex(where: { $0.id == id }) else { return nil }
        return $model.parameters[index]
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let whole = max(0, Int(seconds.rounded(.down)))
        let mins = whole / 60
        let secs = whole % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func logOverlay(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LazyVStack(alignment: .trailing, spacing: 3) {
                        ForEach(Array(model.logEntries.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .id(index)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: maxHeight, alignment: .bottomTrailing)
                .padding(.bottom, 1)
            }
            .scrollIndicators(.hidden)
            .frame(width: min(maxWidth, 560))
            .frame(height: maxHeight, alignment: .bottomTrailing)
            .onAppear {
                guard let last = model.logEntries.indices.last else { return }
                proxy.scrollTo(last, anchor: .bottom)
            }
            .onChange(of: model.logEntries.count) { _, newCount in
                guard newCount > 0 else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newCount - 1, anchor: .bottom)
                }
            }
        }
    }

    private func persistCodePanelFrame(_ rect: CGRect) {}

    private func persistInspectorPanelFrame(_ rect: CGRect) {}

    private func applyEffectsStudioUIState(_ state: EffectsStudioSettings) {
        isApplyingStoredEffectsStudioUIState = true
        panelOpacity = state.panelOpacity
        showCodePanel = state.showCodePanel
        showInspectorPanel = state.showInspectorPanel
        showManifestPanel = state.showManifestPanel
        showLiveControlsPanel = state.showLiveControlsPanel
        showLogOverlay = state.showLogOverlay
        isApplyingStoredEffectsStudioUIState = false
    }

    private func persistEffectsStudioUIState() {
        guard didLoadEffectsStudioUIState, !isApplyingStoredEffectsStudioUIState else { return }
        settingsStore.update { value in
            value.panelOpacity = panelOpacity
            value.showCodePanel = showCodePanel
            value.showInspectorPanel = showInspectorPanel
            value.showManifestPanel = showManifestPanel
            value.showLiveControlsPanel = showLiveControlsPanel
            value.showLogOverlay = showLogOverlay
        }
    }

    private func zIndex(for panel: EffectsStudioPanelID) -> Double {
        guard let index = panelStack.firstIndex(of: panel) else { return 1 }
        return Double(index + 1)
    }

    private func bringPanelToFront(_ panel: EffectsStudioPanelID) {
        guard panelStack.last != panel else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
        panelStack.removeAll { $0 == panel }
        panelStack.append(panel)
        }
    }

    private var codePanelContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Live Metal Code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(model.sourceCode.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            MetalCodeEditorView(text: $model.sourceCode, insertionRequest: $model.pendingCodeInsertion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
    }

    private var inspectorPanelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            parameterDefinitionSection
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var manifestPanelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            manifestInspectorSection
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var liveControlsPanelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            liveControlsSection
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var bottomTransportBar: some View {
        panelCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Menu {
                        Button {
                            model.loadRandomSource(from: state.library, preferredLength: max(2.0, state.settings.clipLengthMaxSeconds))
                        } label: {
                            Label("Random Source", systemImage: "shuffle")
                        }

                        Divider()

                        Button {
                            model.chooseFileSource()
                        } label: {
                            Label("From Files...", systemImage: "doc")
                        }

                        Button {
                            showPhotosPicker = true
                        } label: {
                            Label("From Photos...", systemImage: "photo")
                        }

                        Divider()

                        Button {
                            model.useGeneratedSample()
                        } label: {
                            Label("Use Sample", systemImage: "sparkles")
                        }
                    } label: {
                        Label("Select Source...", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)

                    Spacer(minLength: 0)

                    Text("Source: \(model.inputSourceLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    let duration = max(0.1, model.timelineDuration)
                    Text(formatTime(model.time))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Slider(value: $model.time, in: 0...duration)

                    Button {
                        model.isPlaying.toggle()
                    } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Text(formatTime(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func panelCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var parameterDefinitionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Effect ID (UUID) is managed automatically. Edit Name/Version in the top bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("System params `timeSeconds`, `textureWidth`, and `textureHeight` are host-managed and implicit.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Parameter Definitions")
                    .font(.headline)

                Spacer(minLength: 0)

                Button {
                    model.addParameter()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.editableParameterDefinitions) { parameter in
                        if let parameterBinding = bindingForParameter(id: parameter.id) {
                            EffectsStudioParameterDefinitionRow(
                                parameter: parameterBinding,
                                onChanged: { model.parameterDefinitionDidChange() },
                                onInsert: { name in model.insertParameterUsage(name: name) },
                                onRemove: { model.removeParameter(id: parameter.id) }
                            )
                        }
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var manifestInspectorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Manifest (read-only)")
                .font(.headline)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(model.manifestPreviewJSON)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var liveControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Controls")
                .font(.headline)

            if !model.autoBoundParameterSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Auto-bound (host-driven):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(model.autoBoundParameterSummaries, id: \.self) { summary in
                        Text(summary)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if model.editableParameterNames.isEmpty {
                Text("No editable parameters (all parameters are auto-bound or unnamed).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.editableParameterNames, id: \.self) { name in
                            if let value = model.parameterValue(named: name),
                               let spec = model.parameterSpec(named: name) {
                                ParameterSliderRow(
                                    name: name,
                                    value: value,
                                    effectType: nil,
                                    spec: spec
                                ) { newValue in
                                    model.updateControlParameter(name: name, value: newValue)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func shouldHandleEffectsStudioTab(event: NSEvent) -> Bool {
        guard state.appSettings.keyboardAccessibilityOverridesEnabled else { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isPlainTab = modifiers.isEmpty
        let isShiftTab = modifiers == .shift
        guard event.keyCode == 48, (isPlainTab || isShiftTab) else { return false }

        guard isEffectsStudioWindow(NSApp.keyWindow) else { return false }
        if let eventWindow = event.window, !isEffectsStudioWindow(eventWindow) {
            return false
        }
        return true
    }

    private func isEffectsStudioWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        if window.title == "Effect Studio" {
            return true
        }
        if let parent = window.parent {
            return isEffectsStudioWindow(parent)
        }
        return false
    }

    private func toggleEffectsStudioCleanScreen() {
        if let snapshot = cleanScreenSnapshot {
            // Always restore exactly what was visible when entering clean screen.
            showCodePanel = snapshot.showCodePanel
            showInspectorPanel = snapshot.showInspectorPanel
            showManifestPanel = snapshot.showManifestPanel
            showLiveControlsPanel = snapshot.showLiveControlsPanel
            showLogOverlay = snapshot.showLogOverlay
            showEffectsStudioChrome = snapshot.showChrome

            cleanScreenSnapshot = nil
            focusEffectsStudioHostWindow()
            return
        }

        let hasAnyVisibleOverlay =
            showCodePanel ||
            showInspectorPanel ||
            showManifestPanel ||
            showLiveControlsPanel ||
            showLogOverlay

        // If there is literally nothing visible, clean-screen toggle is a no-op.
        guard hasAnyVisibleOverlay || showEffectsStudioChrome else { return }

            cleanScreenSnapshot = EffectsStudioCleanScreenSnapshot(
                showCodePanel: showCodePanel,
                showInspectorPanel: showInspectorPanel,
                showManifestPanel: showManifestPanel,
                showLiveControlsPanel: showLiveControlsPanel,
                showLogOverlay: showLogOverlay,
                showChrome: showEffectsStudioChrome
            )

        showCodePanel = false
        showInspectorPanel = false
        showManifestPanel = false
        showLiveControlsPanel = false
        showLogOverlay = false
        showEffectsStudioChrome = false
        focusEffectsStudioHostWindow()
    }

    private func focusEffectsStudioHostWindow() {
        guard let studioWindow = NSApp.windows.first(where: { $0.title == "Effect Studio" }) else { return }
        studioWindow.makeKeyAndOrderFront(nil)
    }

    private func queueAutoCompile() {
        guard autoCompile else { return }
        compileGeneration &+= 1
    }
}
