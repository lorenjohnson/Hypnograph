---
doc-status: in-progress
---

# Studio Architecture Refactor

## Overview

This project has now crossed out of the original broad cleanup and into a much more concrete goal: make the primary Hypnograph surface read as one coherent domain, with explicit service seams and honest naming.

The important `HypnoPackages` refactors appear done enough for now. The remaining work is inside `Hypnograph/App/Studio` and in the app-shell wiring around it.

The architecture direction for this pass is:
- `Studio` is the primary viewing/composition/performance surface.
- `EffectsComposer` is the specialized effect-authoring surface.
- `Studio.swift` stays the composition root for the primary surface.
- side effects such as file panels, Photos access, clip-history persistence, and effect-library IO should stay behind explicit services instead of leaking across views.

Target structure for this pass:

```text
Hypnograph/App/Studio
  Studio.swift
  StudioDependencies.swift
  Live/
  Models/
  Persistence/
  Services/
  State/
  Support/
  Views/
```

Decisions for this project:
- `Studio.swift` stays the composition root.
- Moving files between directories is explicitly in scope and considered low risk.
- Matching the intended folder shape is a goal, not just a side effect.
- We are not doing more `HypnoPackages` refactor work here unless a concrete blocker appears.
- We are not doing speculative cleanup just because a file is large.
- The highest-value cleanup is now naming clarity plus Studio-side orchestration and side-effect boundaries.

Current checkpoint:
- The low-risk structural pass is complete.
- The old `Main` domain has been renamed to `Studio`.
- `Studio` now has `Models/`, `Services/`, `State/`, and `Support/` in active use.
- `StudioDependencies.swift` exists and `Studio.swift` now owns explicit panel, Photos, and clip-history persistence seams.
- Direct panel and Photos entry points have been removed from `RightSidebarView`, `AppSettingsView`, and `NoSourcesView`.
- The old broad root action files are gone.
- `PlaybackActions.swift`, `SourceLayerActions.swift`, `HistoryActions.swift`, `GenerationActions.swift`, `ExportActions.swift`, `SessionActions.swift`, `EffectsActions.swift`, `PhotosActions.swift`, `LibraryActions.swift`, and `SettingsPathActions.swift` now hold Studio orchestration in narrower responsibility slices.
- The secondary authoring surface has been renamed from `EffectsStudio` to `EffectsComposer`, including its app-shell window wiring and user-facing labels.

## Rules

- MUST keep behavior stable for playback, history, render/export, live mode, and effect editing.
- MUST treat `Studio.swift` as the composition root for Studio-domain wiring.
- MUST make side effects explicit behind service boundaries where they are currently mixed into views or broad action files.
- MUST keep state/domain mutation paths readable and centralized.
- MUST keep the Studio and Effects Composer names consistent across code, docs, and app shell.
- MUST mirror the intended `Studio` directory shape in this pass.
- MUST NOT use this project to introduce new user-facing features.
- MUST NOT treat `HypnoPackages` as open refactor territory unless a concrete boundary problem is discovered while doing Studio work.
- SHOULD avoid generic abstraction layers when a simple file move or focused type split is enough.
- SHOULD keep view files presentation-focused and remove direct panel/file/Photos orchestration where practical.

## Plan

1. Keep the new folder shape stable. `StudioDependencies.swift`, `State/`, `Services/`, `Models/`, and `Support/` now exist and are doing real work. The point of the next pass is not more directory churn. The point is to keep this shape truthful as we touch code.

2. Keep `Studio.swift` as the composition root and keep service boundaries explicit. File panels, Photos integration, clip-history persistence, and effect-library IO should stay behind dedicated services instead of drifting back into views or broad orchestration files.

3. Keep the narrower state-oriented files under `State/` as the place where Studio orchestration lives:
- `State/PlaybackActions.swift` for play/pause, live send, loop mode, and simple player commands
- `State/SourceLayerActions.swift` for add/remove/duplicate/reorder/select/trim layer operations
- `State/HistoryActions.swift` for history persistence, history navigation, indicator flashing, and history-limit enforcement
- `State/GenerationActions.swift` for random clip generation, append/replace, and clip-end auto-advance behavior
- `State/ExportActions.swift` for snapshot, save, and render/export flows
- `State/SessionActions.swift` for recipe/session loading and append behavior
- `State/EffectsActions.swift` for broad effect-reset commands that still belong to Studio orchestration
- `State/PhotosActions.swift` for Photos authorization/status flow
- `State/LibraryActions.swift` for source-library folder intake
- `State/SettingsPathActions.swift` for settings-backed output and snapshot path selection

4. Keep the naming pass disciplined. `Studio` and `EffectsComposer` are now the intended domain names. Any remaining `Main` or `EffectsStudio` references in live code or live docs should be treated as cleanup bugs, not as acceptable drift.

5. Remove any remaining direct side-effect orchestration from obvious views when encountered, but do not reopen broad UI decomposition work unless a concrete problem appears.

6. Keep the scope disciplined while we do it. We are not prioritizing a deep `PlayerView` refactor unless one of the service seams requires it. We are not splitting `EffectsEditorView` further just because it is large. We are not reopening `HypnoPackages` refactor work unless a concrete Studio boundary problem forces it.

Next phase:
- Review the renamed domains in real implementation work and see whether any of the current state files want different grouping after actual use.
- Keep an eye on any remaining semantic mismatches, but treat `StudioSettings` as the settled name unless a clearer product/domain distinction emerges.

The project is done when all of these are true:
- `Studio` matches the intended top-level directory shape
- the broad root action files are gone
- `Studio.swift` is the clear composition root and dependency entrypoint
- file panels, Photos operations, clip-history persistence, and render/export are behind explicit services
- `EffectsComposer` is the stable name for the effect-authoring surface across code and user-facing strings
- playback/history/render/live behavior still works the same

Verification checklist:
- build succeeds
- history restore/save still works
- new clip / next clip / previous clip / auto-advance still behave correctly
- source add/remove/duplicate/reorder/trim still behave correctly
- save/open/render/snapshot still behave correctly
- live send and live mode behavior remain correct
- effects editing in Studio still behaves correctly
- Effects Composer still opens, previews, edits, and compiles as before
