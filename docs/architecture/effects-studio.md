---
last_reviewed: 2026-02-27T00:00:00Z
---

# Effects Studio Architecture

## Scope
This document describes the current Effects Studio architecture after the 2026-02 refactor.

## Sources

- `Hypnograph/App/EffectsStudio/EffectsStudio.swift`
- `Hypnograph/App/EffectsStudio/Dependencies.swift`
- `Hypnograph/App/EffectsStudio/State/*`
- `Hypnograph/App/EffectsStudio/Services/*`
- `Hypnograph/App/EffectsStudio/Models/*`
- `Hypnograph/App/EffectsStudio/Support/*`
- `Hypnograph/App/EffectsStudio/Views/*`

## Composition Root

- `EffectsStudio.swift` is the feature composition root.
- `Dependencies.swift` defines the feature dependency container and live wiring.
- UI entry points create state/view model with explicit dependencies rather than implicit extension reach-through.

## Layer Boundaries

- `Views/`: SwiftUI layout and event forwarding.
- `State/`: feature state + orchestration.
- `Services/`: side effects (runtime asset IO, Metal compile/render, source playback, panel host windowing).
- `Models/`: pure mapping and schema logic.
- `Support/`: local utilities and shared feature helpers.
- `Persistence/`: Studio settings model + store.

Boundary rule:
- Side effects live in `Services`.
- State mutation lives in `State`.
- Pure data conversion/validation lives in `Models`.

## Current Structure

```text
Hypnograph/App/EffectsStudio
  EffectsStudio.swift
  Dependencies.swift
  Models/
    EffectsStudioParameterModeling.swift
  Services/
    MetalRenderService.swift
    PanelHostService.swift
    RuntimeEffectsService.swift
    SourcePlaybackService.swift
  Persistence/
    EffectsStudioSettings.swift
    EffectsStudioSettingsStore.swift
  State/
    EffectsStudioViewModel.swift
    ManifestParameterState.swift
    MetalRenderState.swift
    RuntimeEffectsState.swift
    SourcePlaybackState.swift
  Views/
    EffectsStudioMetalCodeEditorView.swift
    EffectsStudioPanelWindows.swift
    EffectsStudioParameterDefinitionRow.swift
    EffectsStudioTypes.swift
    EffectsStudioView.swift
  Support/
    EffectsStudioParameterBufferLayout.swift
```

## Runtime Contract

- Runtime manifest bindings (`inputTextures`, `outputTextureIndex`, optional `parameterBufferIndex`) are preserved.
- Temporal behavior remains supported via required lookback history.
- Runtime manifests now use unified `runtimeKind: "metal"` for Metal effects, including temporal ones.

## Verification Status

- Manual feature verification was completed during refactor closure.
- `xcodebuild -project Hypnograph.xcodeproj -scheme Hypnograph -destination 'platform=macOS' build` passes.
- Current test suite (`HypnographTests`, `HypnogramQuickLookTests`) passes.

