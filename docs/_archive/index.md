---
created: 2026-01-21
source: docs/roadmap.md
---

# Roadmap (Completed)

This file is the log of items/projects that have been marked complete and removed from `docs/roadmap.md`.

## Completed Items

- Can do away with lastRecipe, if there is no history or a failure on load we just generate a new hypnogram on start and start a new history

## Recently Completed

- Hold `0` in Montage mode to temporarily suspend global effect chain
- Hold `1-9` in Montage mode to solo source and suspend global effects (keeps source effect for preview)
- Add global Source Framing setting (Fill/Fit) persisted in `hypnograph-settings.json` and applied to preview/live/export
- Change the default location of stored Hypnograms to ~/Movies/Hypnograph ?
- I would like the window state to restore including whether clean screen is currently enabled
- When there were no windows in the saved window state then Tab toggles on all windows... may change this to just being a special keystroke for show all windows but not sure yet
- Move Divine into its own product

## Completed Projects

## Project: Unified Player Architecture
Status: Completed (Superseded by Metal Playback Pipeline)
Shared A/B AVPlayer infrastructure for Preview and Live with smooth transitions; later replaced by the single-surface Metal playback pipeline.
- Docs: `docs/_archive/projects/20260116-unified-player-architecture/overview.md`
- Plan: `docs/_archive/projects/20260116-unified-player-architecture/implementation-planning.md`
- Superseded by: `docs/projects/20260117-metal-playback-pipeline/overview.md`

## Project: Hypnogram Transitions
Status: Completed (Superseded by Metal Playback Pipeline)
Visual transitions between clip changes (Preview + Live), implemented as Metal shader transitions.
- Docs: `docs/_archive/projects/20260116-hypnogram-transitions/overview.md`
- Plan: `docs/_archive/projects/20260116-hypnogram-transitions/implementation-planning.md`
- Superseded by: `docs/projects/20260117-metal-playback-pipeline/overview.md`
