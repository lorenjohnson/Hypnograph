---
doc-status: in-progress
---

# Main Architecture Refactor

## Overview

This project is now narrower than the original spike implied. The important `HypnoPackages`-side refactors appear done enough for now. The remaining architecture work is primarily inside `Hypnograph/App/Main`.

The current `Main` domain is partway through the cleanup already:
- `PlayerState` is a meaningful state boundary.
- `RecordingRenderPipeline` is already separated from the main view layer.
- `SessionFileActions` and `EffectChainLibraryActions` already isolate some file-dialog and import/export behavior.
- `Views/Components` is doing real work and should be kept.

So the remaining problem is not "refactor everything." The remaining problem is that `Main` still has a few broad orchestration files and direct side-effect entry points that make the domain harder to reason about than it needs to be.

What we are trying to achieve in this pass:
- give `Main` the same overall shape as `EffectsStudio`
- make side-effect boundaries explicit
- keep domain mutation centralized and readable
- avoid abstractions that are only decorative

Target structure for this pass:

```text
Hypnograph/App/Main
  Main.swift
  MainDependencies.swift
  Live/
  Models/
  Persistence/
  Services/
  State/
  Support/
  Views/
```

Decisions for this project:
- `Main.swift` stays the composition root.
- Moving files between directories is explicitly in scope and considered low risk.
- Matching the intended folder shape is a goal, not just a side effect.
- We are not doing more `HypnoPackages` refactor work here unless a concrete blocker appears.
- We are not doing speculative cleanup just because a file is large.
- The highest-value cleanup is the Main-side orchestration and side-effect boundaries.

Current checkpoint:
- The low-risk structural pass is complete.
- `Main` now has `Models/`, `Services/`, `State/`, and `Support/` in use.
- `MainDependencies.swift` exists and `Main.swift` now owns explicit panel, Photos, and clip-history persistence seams.
- Direct panel and Photos entry points have been removed from `RightSidebarView`, `AppSettingsView`, and `NoSourcesView`.
- `MainPanelAndPhotosActions.swift` is still an intentional temporary root-level orchestration file.
- The broad root action files are gone.
- `State/MainPlaybackActions.swift`, `State/MainSourceLayerActions.swift`, `State/MainHistoryActions.swift`, `State/MainGenerationActions.swift`, `State/MainExportActions.swift`, `State/MainSessionActions.swift`, and `State/MainEffectsActions.swift` now hold the Main-side orchestration in narrower responsibility slices.

## Rules

- MUST keep behavior stable for playback, history, render/export, live mode, and effect editing.
- MUST treat `Main.swift` as the composition root for Main-domain wiring.
- MUST make side effects explicit behind service boundaries where they are currently mixed into views or broad action files.
- MUST keep state/domain mutation paths readable and centralized.
- MUST mirror the intended `Main` directory shape in this pass.
- MUST NOT use this project to introduce new user-facing features.
- MUST NOT treat `HypnoPackages` as open refactor territory unless a concrete boundary problem is discovered while doing Main.
- SHOULD avoid generic abstraction layers when a simple file move or focused type split is enough.
- SHOULD keep view files presentation-focused and remove direct panel/file/Photos orchestration where practical.

## Plan

1. Establish the `Main` folder shape first. Create the structure we actually want and use it in this pass: `MainDependencies.swift`, `State/`, `Services/`, `Models/`, and `Support/`, alongside the existing `Live/`, `Persistence/`, and `Views/`. Make the low-risk moves early: `PlayerState.swift` into `State/`, `PlayerConfiguration.swift` into `Models/`, and `AudioController.swift`, `SessionFileActions.swift`, and `EffectChainLibraryActions.swift` into `Services/`. This first step is intentionally structural. It should not change behavior. It should just make the domain shape truthful and consistent.

2. Add a real `Main/MainDependencies.swift` and treat `Main.swift` as the composition root. Model this after `EffectsStudio/Dependencies.swift`, but keep it pragmatic. The first version only needs to wire the obvious side-effect seams: session file open/save, effect-chain library file operations, clip-history persistence, render/export, Photos import/write, and file-panel helpers. The goal is not to solve every dependency in one pass. The goal is to stop `Main` and its views from reaching directly into concrete integrations from everywhere.

3. Replace the broad Main action files with narrower state-oriented files under `State/`. The goal is a small set of clearer files, even if they still extend `Main` for now:
- `State/MainPlaybackActions.swift` for play/pause, live send, loop mode, and simple player commands
- `State/MainSourceLayerActions.swift` for add/remove/duplicate/reorder/select/trim layer operations
- `State/MainHistoryActions.swift` for history persistence, history navigation, indicator flashing, and history-limit enforcement
- `State/MainGenerationActions.swift` for random clip generation, append/replace, and clip-end auto-advance behavior
- `State/MainExportActions.swift` for snapshot, save, and render/export flows
- `State/MainSessionActions.swift` for recipe/session loading and append behavior
- `State/MainEffectsActions.swift` for broad effect-reset commands that still belong to Main orchestration

4. Pull the concrete side effects behind explicit services. This is the core of the refactor. The first extractions should be a `ClipHistoryPersistenceService`, a `RenderExportService`, a `PhotosIntegrationService`, and a `PanelHostService` or similarly named file-panel service. These do not need to be elaborate. They just need to own the integrations that are currently leaking across views and broad action files so that Main state/orchestration becomes easier to understand and safer to change.

5. Remove direct side-effect orchestration from the obvious views. The main targets are `RightSidebarView`, `AppSettingsView`, and `NoSourcesView`, which still create panels or handle external integrations directly. This does not mean rewriting every view. It means routing the most obvious file-panel and Photos entry points through Main state/services instead of letting views own them.

6. Keep the scope disciplined while we do it. We are not prioritizing a deep `PlayerView` refactor unless one of the service seams requires it. We are not splitting `EffectsEditorView` further just because it is large. We are not doing stylistic renaming that has no architectural payoff. We are not reopening `HypnoPackages` refactor work unless a concrete Main boundary problem forces it.

Next phase:
- Review whether `MainPanelAndPhotosActions.swift` should stay at the `Main` root, move into `State/`, or dissolve into clearer action files now that the broader split is complete.
- Decide whether any of the new state files should be grouped differently after real use, especially around source curation and session import.
- Keep the next pass focused on naming and remaining orchestration boundaries, not more structural churn for its own sake.

The project is done when all of these are true:
- `Main` matches the intended top-level directory shape
- the broad Main action files are gone
- `Main.swift` is the clear composition root and dependency entrypoint
- file panels, Photos operations, clip-history persistence, and render/export are behind explicit services
- playback/history/render/live behavior still works the same

Verification checklist:
- build succeeds
- history restore/save still works
- new clip / next clip / previous clip / auto-advance still behave correctly
- source add/remove/duplicate/reorder/trim still behave correctly
- save/open/render/snapshot still behave correctly
- live send and live mode behavior remain correct
- effects editing in Main still behaves correctly
