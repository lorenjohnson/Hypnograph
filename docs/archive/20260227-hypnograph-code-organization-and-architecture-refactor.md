# Hypnograph Code Organization and Architecture Refactor

**Date:** 2026-02-27  
**Status:** Completed (archived 2026-02-27)

## Goal

Clarify and simplify app architecture after the runtime-effects + Effect Studio spike, without changing product behavior.

This project is focused on structure and ownership boundaries in the app repo (`Hypnograph`), not on changing the underlying effects runtime in `HypnoCore`.

## Current Shape (As Implemented)

## App-Level Composition

- `App/HypnographApp.swift` defines scenes/windows and wires the app delegate callbacks.
- Two primary windows now exist:
  - Main app window (`WindowGroup("Hypnograph", id: "main")`) via `ContentView`.
  - Studio window (`Window("Effect Studio", id: "effectsStudio")`) via `EffectsStudioView`.
- App menu commands are centralized in `App/AppCommands.swift`, with contextual handling for main-window vs studio-window behavior.

## Main Runtime Roles

- `HypnographState`
  - Global app/library/window-state owner and bridge for app + main settings.
  - Sources/media library activation, settings persistence bridge, window visibility state.
- `Main`
  - Orchestrator for main playback/composition behavior.
  - Owns preview player state, live player, effects sessions, audio controller, and session/history workflows.
- `MainPlayerState`
  - Per-player mutable session/playback/effect application state.

## File/Folder Layout (High Level)

- App code is now rooted under `Hypnograph/App` with explicit domains:
  - `App/` (lifecycle, commands, window registration, app settings)
  - `App/Main/` (main runtime + views + persistence)
  - `App/EffectsStudio/` (studio runtime + views + persistence)
  - `App/Common/` (shared support/utilities/components)
- `SessionStore`, `HypnogramStore`, and main settings persistence live under `App/Main/Persistence`.
- Studio UI/source persistence is now owned by `EffectsStudioSettingsStore` under `App/EffectsStudio/Persistence`.
- `EffectsStudioView.swift` remains large and is targeted for Phase 3 splitting.

## Why It Feels Mismatched

- `Dream` name is legacy from prior modes and does not reflect current product mental model.
- Main-app and studio-app concerns are now both first-class, but code organization still treats studio as an add-on.
- Feature logic and view concerns are intermixed in several places, especially in Studio.
- Root-level app folder has accumulated mixed responsibilities, making ownership less obvious.

## Target Architecture Direction

## Conceptual Domains

- `App`
  - App lifecycle, scenes/windows, menu commands, app delegate wiring.
- `Main` (rename target for `Dream` domain)
  - Main Hypnograph experience (preview/live playback, composition, chain application, clip/session operations).
- `EffectsStudio`
  - Runtime effect authoring, preview/testing, runtime asset CRUD.
- `Common`
  - Cross-domain UI components and neutral reusable utilities.

## Proposed App Repo Layout (Directional)

```text
Hypnograph/
  App/
    HypnographApp.swift
    AppCommands.swift
    WindowRegistration.swift
    AppSettingsStore.swift
    Main/
      MainController.swift               (rename from Dream.swift)
      MainPlayerState.swift              (rename from DreamPlayerState.swift)
      MainAudioController.swift
      LivePlayer.swift
      Persistence/
        MainSettingsStore.swift
        SessionStore.swift
        HypnogramStore.swift
      Views/
        ContentView.swift
        ...main-window-specific views...
    EffectsStudio/
      EffectsStudioViewModel.swift
      EffectsStudioPanelWindowController.swift
      Persistence/
        EffectsStudioSettingsStore.swift
      Views/
        EffectsStudioView.swift
        ...studio-specific components...
    Common/
      Views/
        Components/
      Support/
        Environment.swift
        LegacySessionMigration.swift
```

Notes:

- This is about ownership boundaries first; exact folder names can be tuned.
- Physical file moves can happen before type renames to reduce risk.
- Keep `Main` and `EffectsStudio` relatively flat at first; add deeper subfolders only when needed.
- `HypnogramStore` is treated as `Main` ownership for now; only promote to `Common` if a second domain truly uses it.
- Settings ownership is explicit:
  - `AppSettingsStore` lives in `App/`.
  - `MainSettingsStore` lives in `Main/Persistence`.
  - `EffectsStudioSettingsStore` lives in `EffectsStudio/Persistence`.
  - No shared settings policy in `Common`.

## Naming Recommendation

- Retire `Dream` as primary app-domain name.
- Use `Main` for the main-window runtime domain.
- Keep `EffectsStudio` explicit and separate.

Session naming note (deferred):
- `Session` is currently overloaded (`HypnographSession`, `SessionStore`, `EffectsSession`).
- Treat this as a follow-up cleanup after the structural refactor, not during Phase 1 moves.

Practical approach:

1. Execute Phase 1 in small, mechanical commits (`App` structure + `Dream` → `Main`).
2. Execute Phase 2 settings split (`AppSettings`, `MainSettings`, `EffectsStudioSettings`).
3. Execute Phase 3 audit/convergence and remove temporary compatibility shims.

## What Should Stay in HypnoCore vs App Repo

- Keep in `HypnoCore`:
  - Effects runtime + registry + runtime asset loading and descriptors.
  - Core renderer/effect engine behavior.
- Keep in app repo:
  - Window orchestration.
  - Feature workflows and UX state.
  - Studio interaction model and app-specific tooling UX.

## Refactor Plan (Phased)

## Phase 0: Freeze and Align

- Freeze feature additions briefly.
- Document target boundaries and naming decisions (this doc).
- Lock settings ownership model (`AppSettings`, `MainSettings`, `EffectsStudioSettings`).
 - Status: complete.

## Phase 1: Structural Move + Main Rename

- Create `App/` with nested `Main`, `EffectsStudio`, and `Common` folders.
- Move files to target folders with minimal behavior change.
- Rename `Dream` symbols to `Main` symbols as part of this phase.
- Narrow `HypnographState` to app-global concerns only.
- Keep composition-specific runtime state in the `Main` domain.
 - Status: complete.

## Phase 2: Settings Split

- Split settings into three stores:
  - `AppSettingsStore` for app-global policy.
  - `MainSettingsStore` for main-window playback/composition defaults.
  - `EffectsStudioSettingsStore` for studio editor/panel behavior.
- Move `SessionStore` under `Main/Persistence` unless Effects Studio gains real usage.
- Keep `Common` free of domain settings ownership.
 - Status: complete (`AppSettingsStore`, `MainSettingsStore`, `EffectsStudioSettingsStore` wired).

## Phase 3: Audit and Convergence

- Do a focused code audit after structural changes settle.
- Consider extracting `HypnographAppDelegate` into its own file for clarity (if still beneficial).
- Split oversized files where needed (especially Studio) while preserving behavior.
- Remove obsolete legacy naming and consolidate helper patterns.
- Verify command routing, keyboard context handling, and multi-window lifecycle behavior.

## Immediate Decisions Needed Before Large Moves

1. Final replacement name for `Dream` domain (`Main` selected).
2. Studio settings policy:
   - Selected: `AppSettings` + `MainSettings` + `EffectsStudioSettings`.
   - `Common` contains reusable utilities, not shared settings policy.
3. Whether to complete effects conversion first or perform file-organization first.
   - Selected: perform file-organization first (Phase 1), then settings split (Phase 2).

## Recommended Next Step

Proceed with Phase 3: targeted audit/split of oversized files (starting with `EffectsStudioView` and optionally `HypnographAppDelegate`) plus cleanup of deferred naming/session terminology.


## Completion Summary

- Phase 0 completed (scope and naming/settings policy alignment).
- Phase 1 completed (App/Main/EffectsStudio/Common structural reorganization and Dream->Main transition).
- Phase 2 completed (settings split to AppSettings/MainSettings/EffectsStudioSettings).
- Phase 3 initiated via follow-on project: `active/hypnograph-code-audit-and-convergence.md`.
