---
doc-status: done
---

# FX Studio Architecture Refactor

## Goal

Refactor Effects Composer into a clear, durable feature architecture that is easier to evolve without regressions.

Primary objectives:
- Reduce hidden coupling and implicit internal APIs.
- Replace "big type split across extensions" with explicit feature boundaries.
- Keep behavior stable while making future work safer and faster.

## Why Now

Recent work proved the feature direction, but left high internal complexity in Studio files.

Known pressure points:
- Large files with mixed concerns.
- Broad extension surface area (`Type+Concern.swift`) with implicit internal contracts.
- Side effects (IO, compile, render, windowing, playback) mixed with state orchestration.

## Current Snapshot (2026-02-27)

Current file layout under `Hypnograph/App/EffectsComposer`:

```text
Models/
  EffectsComposerParameterModeling.swift

Services/
  MetalRenderService.swift
  PanelHostService.swift
  RuntimeEffectsService.swift
  SourcePlaybackService.swift

Persistence/
  EffectsComposerSettings.swift
  EffectsComposerSettingsStore.swift

State/
  EffectsComposerViewModel.swift
  ManifestParameterState.swift
  MetalRenderState.swift
  RuntimeEffectsState.swift
  SourcePlaybackState.swift

Views/
  EffectsComposerMetalCodeEditorView.swift
  EffectsComposerPanelWindows.swift
  EffectsComposerParameterDefinitionRow.swift
  EffectsComposerTypes.swift
  EffectsComposerView.swift

Support/
  EffectsComposerParameterBufferLayout.swift
```

Current concentration of logic (line count):
- `State/EffectsComposerViewModel.swift` + state slices: ~1185 lines total.
- Runtime effects orchestration: `State/RuntimeEffectsState.swift`.
- Compile/render orchestration: `State/MetalRenderState.swift`.
- Source orchestration/playback loop: `State/SourcePlaybackState.swift`.
- Manifest synthesis and parameter schema orchestration: `State/ManifestParameterState.swift`.

## Scope

### In Scope
- Effects Composer code organization and boundaries.
- Dependency boundary design and implementation for Studio collaborators.
- Studio-only naming/structure cleanup aligned with the new architecture.
- Build verification after each phase.

### Out of Scope
- Main app architecture refactor (follow-up project).
- New end-user feature additions.
- Runtime effect file format redesign.
- Cross-repo redesign in `HypnoCore` unless strictly required for Studio wiring.

## Target Structure

```text
Hypnograph/App/EffectsComposer
  EffectsComposer.swift
  Dependencies.swift

  Views/
  State/
  Models/
  Services/
  Persistence/
  Support/
```

Notes:
- Keep names concise inside this feature folder (no redundant `EffectsComposer*` prefix unless needed to avoid collisions).
- Favor explicit feature types over large extension-file slices.
- `EffectsComposer.swift` is the composition root; it wires dependencies and initializes state/view model.

## Architecture Invariants

These behaviors must remain correct throughout the refactor:
- Studio preview must honor runtime manifest bindings (`inputTextures`, `outputTextureIndex`, optional `parameterBufferIndex`).
- Temporal/history effects must preserve current behavior (history texture lookup + lookback behavior).
- Phase 1 and Phase 2 are structure-focused and must not intentionally change user-visible behavior.

## Boundary Rules

- `Views/`: SwiftUI composition/layout only.
- `State/`: observable state + orchestration; minimal side-effect code.
- `Models/`: domain models, mappings, and pure rules.
- `Services/`: side-effectful integrations (runtime asset IO, compile/reflection, render, source loading/playback clock, panel host).
- `Persistence/`: Studio settings persistence only.
- `Support/`: small shared utility types/constants local to Studio.

Service scope rule:
- A service should own side effects (Metal/AppKit/IO/Photos/timers/tasks).
- Pure mapping/validation/default-resolution logic belongs in `Models/`.

## Dependency Strategy

Studio gets collaborators through a local dependency container:
- `Dependencies.swift` defines required collaborator protocols and `live` implementations.
- `EffectsComposer.swift` creates and injects dependencies into state/view model.

Purpose:
- Make boundaries explicit.
- Enable local previews/tests with fakes.
- Avoid direct reach-through from Studio state into concrete implementations.

## API Surface Rules

- Avoid creating new broad `Type+Concern` internal surfaces.
- Prefer small explicit types with narrow, responsibility-specific interfaces.
- Keep state mutation centralized in state-layer types.

## Migration Plan

### Phase 1: Structure + Composition Root

- [x] Add `EffectsComposer.swift` composition root.
- [x] Add `Dependencies.swift` and `live` wiring.
- [x] Create `State/`, `Models/`, `Services/`, `Support/` folders.
- [x] Keep behavior unchanged in this phase.

Phase gate:
- [x] Build passes and Studio behavior is unchanged.

### Phase 2: Model + Support Extraction

- [x] Move pure parameter/manifest mapping and sanitization logic into `Models/`.
- [x] Move buffer layout/support structs (`EffectsComposerParamBufferLayout`, etc.) into `Support/` or `Models/` as appropriate.
- [x] Keep state mutation in state layer, keep conversion rules pure.

Phase gate:
- [x] No behavior drift; logic moved is pure and has no side effects.

### Phase 3: Service Extraction

- [x] Extract runtime effect asset IO into a `RuntimeEffectsService`.
- [x] Extract Metal compile/render/reflection into a `MetalRenderService`.
- [x] Extract source load/playback/frame extraction into a `SourcePlaybackService`.
- [x] Extract panel/window side effects behind a panel host service.

Phase gate:
- [x] Old side-effect paths are removed after extraction (no duplicated active paths).

### Phase 4: State Consolidation

- [x] Reduce `EffectsComposerViewModel` to orchestration and published state.
- [x] Replace extension-heavy surface with explicit state/coordinator types in `State/`.
- [x] Remove dead code paths left from transition.

Phase gate:
- [x] State layer owns orchestration only; side effects are dependency-driven.

### Phase 5: Verification + Cleanup

- [x] Full macOS build verification.
- [x] Manual behavior verification for compile, preview, source playback, and panel operations.
- [x] Update docs with resulting architecture decisions and file map.

Phase gate:
- [x] Regression checklist passes, including temporal runtime effects.

## Initial File Move Map

This map is the starting point and can be adjusted during extraction:

- `Views/EffectsComposerViewModel+ManifestParameters.swift` -> split across `Models/` (pure manifest/parameter mapping) and `State/` (mutation hooks).
- `Views/EffectsComposerViewModel+MetalRender.swift` -> `Services/MetalRenderService.swift` + state orchestration calls in `State/`.
- `Views/EffectsComposerViewModel+RuntimeEffects.swift` -> `Services/RuntimeEffectsService.swift` + state orchestration in `State/`.
- `Views/EffectsComposerViewModel+SourcePlayback.swift` -> `Services/SourcePlaybackService.swift` + state orchestration in `State/`.
- `Views/EffectsComposerPanelWindows.swift` -> `Services/PanelHostService.swift` (or keep thin UI glue in `Views/` and move host side effects to service).
- `Views/EffectsComposerTypes.swift` -> split into `Models/` and `Support/` based on concern.

## Verification Checklist

- [x] `xcodebuild -project Hypnograph.xcodeproj -scheme Hypnograph -destination 'platform=macOS' build` passes.
- [x] Effects list load/save/delete still works.
- [x] Studio compile + live preview still works for simple and temporal effects.
- [x] Explicit temporal checks pass in Studio for: Ghost Blur, Color Echo, Frame Difference.
- [x] Source selection (random/files/photos/sample) + playback behavior still works.
- [x] Source switch + recompile + playback still updates output correctly for temporal effects.
- [x] Panel window behavior (show/hide/move/resize/clean-screen) still works.

Verification notes (2026-02-27):
- Manual Studio behavior checks were completed by user and reported as passing.
- Temporal runtime effect manifests for Ghost Blur, Color Echo, and Frame Difference were verified in `HypnoPackages/HypnoCore/Renderer/Effects/RuntimeAssets/*/effect.json` with unified `runtimeKind: "metal"` and expected lookback bindings.
- `xcodebuild ... test` now passes after updating stale `HypnogramTests.swift` references (`Settings` -> `MainSettings`) and removing the obsolete empty `HypnographUITests` target.
- Local runtime effect cache under `~/Library/Application Support/Hypnograph/runtime-effects` was normalized to unified `runtimeKind: "metal"` for legacy temporal entries.

## Risks and Mitigations

- Risk: behavior drift while extracting side effects.
  - Mitigation: phase-by-phase extraction with build + manual checks each phase.
- Risk: unclear ownership between state and services.
  - Mitigation: keep service API side-effect-focused; keep state mutation in state layer.
- Risk: extension removal creates oversized replacement types.
  - Mitigation: prefer small, explicit types by responsibility instead of one new large coordinator.

## Deliverables

- Refactored Effects Composer architecture with explicit boundaries.
- Updated docs for resulting architecture decisions.
- Follow-up handoff doc for analogous Main app architecture refactor.

## Follow-up Project

After this project: create and run **Main App Architecture Refactor** using aligned patterns where appropriate.
