---
created: 2026-01-21
updated: 2026-01-21
---

## Roadmap (Completed / Archived)

- [x] Hold `0` in Montage mode to temporarily suspend global effect chain
- [x] Hold `1-9` in Montage mode to solo source and suspend global effects (keeps source effect for preview)
- [x] Add global Source Framing setting (Fill/Fit) persisted in `hypnograph-settings.json` and applied to preview/live/export
- [x] Move Divine into its own product
- [x] Can do away with lastRecipe, if there is no history or a failure on load we just generate a new hypnogram on start and start a new history
- [x] Clip slicing: for video sources, preserve a random `startTime` when it can play continuously for `targetDuration` without hitting the end; otherwise clamp `startTime` back so it can play to the end without looping; if the asset is shorter than `targetDuration`, use `startTime = 0` and loop the full asset.
- [x] Flash of image before processed in Player should be avoided/eliminated. Add a Transitions setting for what happens between Hypnograms. Maybe a Player setting for Transition Style with options: None, Fade, Punk (random dissolve)?
- [x] Vision smart framing (Human Centering): bias `SourceFraming.fill` toward detected subjects without revealing edges.
- [x] Project: Unified Player Architecture: Shared A/B player infrastructure for Preview and Live with smooth transitions. Foundational work for transitions and volume leveling. Docs: `docs/projects/20260116-unified-player-architecture/overview.md`, Plan: `docs/projects/20260116-unified-player-architecture/implementation-planning.md`
- [x] Project: Hypnogram Transitions. Visual transitions between clip changes (Preview + Live). Depends on: Unified Player Architecture. Docs: `docs/projects/20260116-hypnogram-transitions/overview.md`, Plan: `docs/projects/20260116-hypnogram-transitions/implementation-planning.md`
