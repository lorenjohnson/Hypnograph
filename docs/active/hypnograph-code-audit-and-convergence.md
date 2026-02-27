# Hypnograph Code Audit and Convergence

**Date:** 2026-02-27  
**Status:** Active

## Goal

Run a focused post-refactor audit to tighten architecture, remove dead/legacy code paths, and reduce future regression risk without changing user-visible behavior.

This follows completion of the app-structure/settings split refactor and focuses on convergence quality.

## Scope

### In Scope
- Main-app and Effects Studio code quality audit.
- Dead-code and compatibility-shim cleanup where safe.
- Naming convergence from legacy `dream` terminology toward `main` terminology at safe boundaries.
- Small structural decompositions where files are still oversized and mixed-concern.
- Command routing and multi-window keyboard context verification.

### Out of Scope
- New end-user features.
- Major UX redesign.
- Runtime effect format redesign.
- Cross-repo effects architecture changes in `HypnoCore` beyond compatibility fixes needed by app behavior.

## Current Baseline

- Effects Studio split completed into dedicated files (`view`, `view model`, `types`, `panel windows`, `parameter row`, code editor bridge).
- App delegate extracted to dedicated lifecycle file.
- Settings split completed (`AppSettings`, `MainSettings`, `EffectsStudioSettings`).
- Live feature UI components moved under `App/Main/Live/Views/Components`.
- Unused `ModalPanel` path removed after call-site verification.
- Builds passing locally.

## Audit Priorities

## Priority 1 — Correctness and Compatibility
- Verify session file enumeration supports all declared session extensions (`.hypno`, `.hypnogram`) in list/read paths.
- Verify command/context routing is deterministic when Main and Effects Studio windows are both open.
- Verify clean-screen toggles are correctly scoped to active window context.

## Priority 2 — Dead Code and Redundant Paths
- Remove inactive in-view floating panel state/logic in Effects Studio now superseded by AppKit panel hosts.
- Remove obsolete aliases and comments that imply active migration state when migration is already complete.
- Keep only compatibility code that still protects real persisted data in current local usage.

## Priority 3 — Naming Convergence
- Perform an incremental naming sweep from `dream` to `main` at app wiring boundaries first.
- Defer deep symbol churn to staged follow-ups where rename blast radius is high.
- Preserve API stability where broad rename would create unnecessary risk in the same pass.

## Priority 4 — Hotspot Decomposition
- Continue splitting oversized mixed-concern files:
  - `App/Main/Main.swift`
  - `App/Main/Views/EffectsEditorView.swift`
  - `App/EffectsStudio/Views/EffectsStudioViewModel.swift`
- Extract seams by concern (state orchestration, IO, rendering helpers, UI adapters).

## Work Plan

1. Correctness fixes discovered in audit (small, isolated patches).
2. Remove dead/duplicate paths and stale compatibility shims.
3. Apply safe naming convergence at boundary layers.
4. Perform targeted extractions for remaining hotspot files.
5. Re-run build and core behavior checks after each batch.
6. Produce final audit summary with findings, changes, and remaining follow-ups.

## Verification Checklist

- `xcodebuild -project Hypnograph.xcodeproj -scheme Hypnograph -configuration Debug -destination 'platform=macOS' build` passes.
- Main window and Effects Studio both open/close cleanly.
- Clean-screen command behavior is context-correct for active window.
- Session open/list behavior includes both `.hypno` and `.hypnogram` where intended.
- Effects Studio compile/preview/parameter editing behavior unchanged.

## Deliverables

- Code cleanup commits grouped by audit priority.
- Updated docs reflecting completed cleanup and deferred follow-ups.
- Final audit report (what changed, what was intentionally deferred, and risk notes).

## Exit Criteria

This project is complete when:
- High-confidence correctness issues identified in audit are resolved.
- Dead code paths introduced by refactor transition are removed.
- Naming and structure are materially clearer at app boundary layers.
- Build and core multi-window workflows remain stable.

## Current Working Notes (2026-02-27)

- Confirmed naming collision between app-level `PlayerView` and `HypnoCore.PlayerView`.
- Decided direction: rename HypnoCore render-surface type from `PlayerView` to `RendererView` to keep app-level `PlayerView` user-facing.
- Completed: HypnoCore docs/ontology references updated to match `RendererView`.
- Treat the HypnoCore rename as a breaking API change for external consumers; use a conventional-commits style message and bump package version before merge.
- Main app cleanup to evaluate now:
  - Completed: moved `PlayerView` and `PlayerContentView` under `App/Main/Views`.
  - Completed: moved `LivePlayer` and `LiveWindow` into `App/Main/Live`.
  - Completed: moved `LivePreviewPanel` and `LivePlayerScreen` into `App/Main/Live/Views/Components`.
  - Completed: removed unused `ModalPanel` / `ModalPanelStyle.livePreview`.
  - Completed: renamed primary audio symbols from `preview*` to neutral names (`audioDevice`, `volume`) across Main/UI/controller/settings.
  - Completed: added temporary backward-compatible decode for legacy settings keys (`previewAudioDeviceUID`, `previewVolume`) while writing new keys (`audioDeviceUID`, `volume`).
  - Completed: command routing for clean-screen now resolves deterministic active window context (key window first, then main window).
  - Verified: session extension handling is consistent for `.hypno` + `.hypnogram` in list/filter/open paths (`SessionStore.fileExtensions`, `isSupportedExtension`, `listSavedRecipes`, and open/save panel type filters).
  - Verified: clean-screen keyboard scopes remain context-correct (`HypnographAppDelegate` handles Main-only tab override; Effects Studio has its own local tab monitor).
  - P2 cleanup note: no remaining in-view floating panel drag/resize state from pre-AppKit host architecture was found; panel behavior is owned by `EffectsStudioPanelWindows` + NSPanel autosave.
  - Completed: removed stale compatibility-only dead methods from `EffectsEditorViewModel` (`syncFromConfig`, legacy no-layer selection overloads) after call-site verification.
  - Completed: removed stale migration/phase wording in compatibility code comments while retaining only active persisted-data protections (`PlayerConfiguration` fallback key, `HypnogramStore.recipeURL`, `LegacySessionMigration` rewrite path); removed obsolete `preview*` audio decode fallbacks from `MainSettings`.
  - Verified: no remaining app-boundary `dream` naming in source code (`App/**`); no additional P3 rename required in this pass.
  - Follow-on architecture: move toward per-window key routers (`MainKeyRouter`, `EffectsStudioKeyRouter`) and reduce `HypnographAppDelegate` to lifecycle/event wiring only.
  - P4 status: `EffectsEditorView` decomposition pass is complete and build-verified (`EffectsEditorViewModel`, `EffectsEditorField`, `EditableEffectNameHeader`, and `EffectDropDelegate` extracted to dedicated files).
  - P4 completed: `EffectsStudioViewModel.swift` decomposition is now build-verified across focused files:
    - `EffectsStudioViewModel.swift` (core state/init shell)
    - `EffectsStudioViewModel+RuntimeEffects.swift`
    - `EffectsStudioViewModel+ManifestParameters.swift`
    - `EffectsStudioViewModel+MetalRender.swift`
    - `EffectsStudioViewModel+SourcePlayback.swift`
  - P4 completed: `Main.swift` decomposition is now build-verified by concern seams:
    - `Main.swift` (core state/init/display shell)
    - `ClipHistoryAndLayerActions.swift`
    - `SessionAndSourceActions.swift`
  - Follow-up naming cleanup: decide whether to keep `Type+Concern.swift` filenames for extension-backed splits or rename to domain-oriented files without `+` while preserving the same behavior.
