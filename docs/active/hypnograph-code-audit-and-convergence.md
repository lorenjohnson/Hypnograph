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
