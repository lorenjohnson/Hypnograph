---
doc-status: in-progress
---

# Overview

Playback and panel code in Studio has become harder to hold in one’s head. The behavior still mostly works, but understanding or changing it often means jumping across too many files and reconstructing ownership mentally.

This project is to make those subsystems easier to understand and safer to change. The goal is not to introduce architecture for its own sake. The goal is to consolidate ownership where it is currently too scattered, move related files into clearer places when that genuinely helps, and stop once the result is meaningfully easier to reason about.

The guiding idea is simple:
- clearer ownership
- fewer files to inspect to understand what happens next
- less orchestration living implicitly in view files
- no new abstraction unless it immediately reduces complexity

`Coordinator` is the chosen naming direction for runtime orchestration objects in this work. We should also reduce unnecessary `preview` naming where `playback` or `rendering` is the more honest term.

## Scope

- MUST make playback behavior easier to locate and understand without introducing speculative framework code.
- MUST make panel infrastructure easier to locate and understand without inventing artificial boundaries.
- MUST use `Coordinator` consistently for this class of runtime orchestration object.
- SHOULD move related files into feature-scoped areas when doing so makes the code easier to navigate.
- SHOULD reduce orchestration burden in view files where that improves clarity.
- SHOULD reduce unnecessary `preview` naming in playback-related code.
- MAY move related views with their subsystem if that makes the boundary clearer in practice.
- MUST NOT add abstraction that does not immediately simplify ownership or behavior.

## Plan

- Start with playback, since it is currently the subsystem with the highest mental overhead and the most visible edge-case pressure.
- Consolidate playback orchestration into a clearer owner and move the related files into a more legible structure.
- Then do the same review for panels, moving infrastructure and views together only if that actually improves clarity.
- Stop when the code is noticeably easier to understand and modify, rather than trying to force a perfectly pure architecture.

Current implementation direction in this branch:
- `PlayerView` and `PlayerContentView` move into `Studio/Playback/Views/`
- `PlayerState` and `PlaybackActions` move into `Studio/Playback/State/`
- the former nested playback runtime owner becomes a top-level `PlayerPlaybackCoordinator`
- panel runtime files move into `Studio/Panels/`
- `PanelStateController` becomes `PanelStateCoordinator`
- `PanelHostService` becomes `PanelHostCoordinator`
- panel-only bridge and helper views move with the panel subsystem where that improves clarity

Current playback/rendering note:
- `RenderEngine.Config` now has a `useSourceFrameRate` option.
- Playback currently opts into this so preview can use source-derived cadence when the composition's video layers agree on one frame rate.
- Export does not currently opt into it, so sequence/current render still use the configured output frame rate.
- This is intentional for now: the shared render engine exposes the capability, while playback is the only caller using it until render semantics are designed more explicitly.

## Open Questions

- Does playback become clearer with one top-level coordinator, or with one primary coordinator plus a very small number of helpers?
- Should panel views move with panel infrastructure immediately, or only where the feature boundary becomes clearer by doing so?
