---
doc-status: done
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

## Completion Notes

This refactor pass is complete.

What landed:
- `Main` was renamed to `Studio`, giving the primary Hypnograph surface a real domain name.
- `EffectsStudio` was renamed to `EffectsComposer`, keeping the specialized effect-authoring surface distinct from the main Studio surface.
- `Studio.swift` and `StudioDependencies.swift` now act as the clear composition root and dependency seam for the primary surface.
- `Studio` now uses the intended directory shape in practice: `Models/`, `Persistence/`, `Services/`, `State/`, `Support/`, `Views/`, and `Live/`.
- the broad root action files were replaced with narrower state files such as `PlaybackActions.swift`, `SourceLayerActions.swift`, `HistoryActions.swift`, `GenerationActions.swift`, `ExportActions.swift`, `SessionActions.swift`, `EffectsActions.swift`, `PhotosActions.swift`, `LibraryActions.swift`, and `SettingsPathActions.swift`.
- file panels, Photos integration, clip-history persistence, and effect-library IO are now behind explicit services instead of leaking across views.
- `WorkspaceSettings` and `WorkspaceSettingsStore` were settled as `StudioSettings` and `StudioSettingsStore`.

Verification:
- build succeeds
- runtime checks passed for playback, history navigation, source/layer operations, save/open/render/snapshot flows, live mode, and Effects Composer behavior

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
