# FX Studio Architecture Refactor

**Date:** 2026-02-27  
**Status:** Active

## Goal

Refactor Effects Studio into a clear, durable feature architecture that is easier to evolve without regressions.

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

## Scope

### In Scope
- Effects Studio code organization and boundaries.
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
App/EffectsStudio
  EffectsStudio.swift
  Dependencies.swift

  Views/
  State/
  Models/
  Services/
  Persistence/
  Support/
```

Notes:
- Keep names concise inside this feature folder (no redundant `EffectsStudio*` prefix unless needed to avoid collisions).
- Favor explicit module boundaries over large extension-file slices.

## Boundary Rules

- `Views/`: SwiftUI composition/layout only.
- `State/`: observable state + orchestration; minimal side-effect code.
- `Models/`: domain models, mappings, and pure rules.
- `Services/`: side-effectful integrations (runtime asset IO, compile/reflection, render, source loading/playback clock, panel host).
- `Persistence/`: Studio settings persistence only.
- `Support/`: small shared utility types/constants local to Studio.

## Dependency Strategy

Studio gets collaborators through a local dependency container:
- `Dependencies.swift` defines required collaborators and a `live` wiring.
- `EffectsStudio.swift` is the feature entry/composition root.

Purpose:
- Make boundaries explicit.
- Enable local previews/tests with fakes.
- Avoid direct reach-through from Studio state into concrete implementations.

## Plan

1. Create the new folder/file skeleton (no behavior changes).
2. Move code by concern into `Views/State/Models/Services/Persistence/Support`.
3. Introduce Studio dependency container and composition root.
4. Collapse extension-surface APIs into explicit types where practical.
5. Validate runtime compile/preview/source workflows and panel behavior.
6. Remove stale transitional structures once replacement paths are stable.

## Verification Checklist

- `xcodebuild -project Hypnograph.xcodeproj -scheme Hypnograph -destination 'platform=macOS' build` passes.
- Effects list load/save/delete still works.
- Studio compile + live preview still works for simple and temporal effects.
- Source selection (random/files/photos/sample) + playback behavior still works.
- Panel window behavior (show/hide/move/resize/clean-screen) still works.

## Deliverables

- Refactored Effects Studio architecture with explicit boundaries.
- Updated docs for resulting architecture decisions.
- Follow-up handoff doc for analogous Main app architecture refactor.

## Follow-up Project

After this project: create and run **Main App Architecture Refactor** using aligned patterns where appropriate.
