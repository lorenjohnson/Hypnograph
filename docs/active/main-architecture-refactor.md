---
doc-status: in-progress
---

# Main Architecture Refactor

## Overview

Apply the same architectural cleanup pattern used for Effects Studio to the Main feature domain, with explicit boundaries and lower coupling, while preserving behavior.

Primary objectives:
- Make Main feature ownership clearer (`State`, `Services`, `Models`, `Views`, `Persistence`, `Support`).
- Reduce orchestration/side-effect mixing in Main action files.
- Keep playback/render/export behavior stable while making future changes safer.

### Why Now

The Main domain has accumulated substantial logic across coordinator/action files and large views. It works, but the mental model and extension surface are harder than necessary.

Current pressure points:
- Large mixed-concern files in Main feature orchestration and views.
- Side effects (render, file IO, Photos, persistence, notifications) intermixed with state mutation paths.
- Implicit contracts between Main orchestration and view callbacks.

### Current Snapshot (2026-02-27)

`Hypnograph/App/Main` currently includes:
- Core orchestration:
  - `Main.swift` (~298 lines)
  - `SessionAndSourceActions.swift` (~617 lines)
  - `ClipHistoryAndLayerActions.swift` (~573 lines)
  - `RecordingRenderPipeline.swift` (~301 lines)
- High-complexity UI surfaces:
  - `Views/EffectsEditorView.swift` (~974 lines)
  - `Views/AppSettingsView.swift` (~580 lines)
  - `Views/PlayerView.swift` (~574 lines)
  - `Views/PlayerContentView.swift` (~486 lines)
- Existing feature folders:
  - `Live/`, `Persistence/`, `Views/`

Total swift lines under `App/Main` (including persistence + views): ~8204.

## Rules

- MUST focus on Main feature architecture and boundary cleanup.
- MUST preserve current playback/render/export behavior during refactor.
- MUST keep `Main.swift` as composition root for Main-domain wiring.
- MUST keep side effects behind service boundaries and keep state mutation centralized.
- MUST NOT add new end-user features in this project.
- MUST NOT redesign Effects runtime in `HypnoCore`.
- MUST NOT introduce Studio architecture changes (handled in a separate project).
- SHOULD keep `Views/` presentation-focused and avoid direct side-effect orchestration in view code.

### Target Structure

```text
Hypnograph/App/Main
  Main.swift
  Dependencies.swift

  State/
  Services/
  Models/
  Views/
  Persistence/
  Live/
  Support/
```

Notes:
- Keep `Main.swift` as composition root for Main-domain wiring.
- Prefer explicit feature types over broad action-file catch-alls.
- Keep `Views/` focused on UI composition; move side effects behind services.

### Architecture Invariants

These behaviors must remain correct during the refactor:
- Edit/Live mode switching and live preview behavior.
- Clip history navigation, creation, and persistence.
- Source selection, clip trim/range behavior, and layer operations.
- Render/export/snapshot behavior (including save destination policy).
- Effect chain editing behavior in Main sidebars/editors.

### Boundary Rules

- `State/`: observable Main state + mutation/orchestration logic.
- `Services/`: side-effect integrations (render/export, IO, Photos, timers, notifications, open/save panels).
- `Models/`: pure mapping/validation/default rules.
- `Views/`: SwiftUI presentation and user interaction only.
- `Persistence/`: stores and file codable contracts only.
- `Support/`: local utilities/constants that are not domain state.

### Dependency Strategy

- Add `Main/Dependencies.swift` with narrow protocols and live implementations for side effects.
- Inject dependencies into Main orchestration/state, instead of reaching directly into concrete integrations from multiple files.
- Keep service APIs small and responsibility-specific.

## Plan

### Phase 1: Composition Root + Dependency Container

- [ ] Add `Main/Dependencies.swift` (protocols + live wiring).
- [ ] Keep `Main.swift` as composition root; wire dependencies there.
- [ ] Ensure no intentional behavior changes.

Phase gate:
- [ ] Build passes and Main behavior is unchanged.

### Phase 2: State Consolidation

- [ ] Move mutation/orchestration from broad action files into explicit `State/` types.
- [ ] Keep Main feature state mutation centralized.
- [ ] Reduce implicit contracts between views and ad-hoc action methods.

Phase gate:
- [ ] Session/history/source mutation behavior remains unchanged.

### Phase 3: Service Extraction

- [ ] Extract render/export orchestration behind a Main service boundary.
- [ ] Extract file open/save and Photos side effects behind services.
- [ ] Extract timer/task/persistence side effects (history save cadence, notifications) behind services where appropriate.

Phase gate:
- [ ] Duplicated side-effect paths are removed after extraction.

### Phase 4: View/Editor Boundary Cleanup

- [ ] Split oversized Main views where needed to reduce mixed UI/logic.
- [ ] Ensure view models own UI state; services/state own side effects and domain mutation.
- [ ] Minimize direct side-effect calls from view bodies.

Phase gate:
- [ ] Main views compile cleanly with reduced orchestration leakage.

### Phase 5: Verification + Cleanup

- [ ] Run full build/test verification.
- [ ] Perform manual behavior checks for playback, live mode, trim, history, and render/export.
- [ ] Update architecture docs and roadmap status.

Phase gate:
- [ ] Regression checklist passes.

### Verification Checklist

- [ ] `xcodebuild -project Hypnograph.xcodeproj -scheme Hypnograph -destination 'platform=macOS' build` passes.
- [ ] Clip history navigation and persistence behavior remain correct.
- [ ] Source/layer edits (add/remove/duplicate/reorder/trim) remain correct.
- [ ] Edit/Live mode behavior remains correct.
- [ ] Render/snapshot/save workflows remain correct.
- [ ] No functional regressions in right-sidebar effects editing.

### Risks and Mitigations

- Risk: behavior drift while extracting services/state.
  - Mitigation: phase gates + manual verification after each phase.
- Risk: replacing one large file with another.
  - Mitigation: enforce narrow role boundaries and explicit dependency contracts.
- Risk: persistence/side-effect race conditions.
  - Mitigation: isolate timers/tasks in service boundaries and keep state writes centralized.

### Deliverables

- Main feature refactor with explicit `State`/`Services`/`Models` boundaries.
- Reduced mixed-concern orchestration in Main domain files.
- Updated documentation and verification notes.
