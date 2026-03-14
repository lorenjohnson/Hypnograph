# Preview Frame Buffer Bleed Between Clips

**Project ID:** preview-frame-buffer-bleed-between-clips
**Status:** Backlog
**Created:** 2026-03-14

## Goal

Eliminate preview-only temporal/frame-buffer bleed between clips so clip navigation and clip-range edits do not carry prior-clip history into the currently viewed clip.

## Reported Behavior

- Intermittent bleed from previous clip state appears in preview when switching clips (especially previous/next navigation and some trim/start-point changes).
- Export/render output is generally correct, so this appears localized to preview pipeline state handling.

## Reproduction Notes

- Most visible with temporal effects active (notably `FrameDifference` and `IFrameCompress`).
- Most frequent when rapidly switching between clips or changing clip range/start and immediately replaying.
- Can be intermittent; sometimes preview is clean.

## What Was Tried (Concise)

- Clearing frame buffer at clip switch and at clip trim updates.
  - Reduced bleed in some paths, but did not fully eliminate it.
- Freezing outgoing effect context for transitions, including clip snapshot cloning.
  - Improved isolation in some cases, but did not fully eliminate bleed.
- Timing/order adjustments around clip-switch state reset and transition setup.
  - Changed behavior profile, but intermittent bleed remained.
- Additional temporal-generation guard attempts.
  - Did not fully resolve intermittent bleed.

Note:
- Transition black-flash/cut artifacts were observed in several attempted fixes, but that is not the baseline issue and is not the primary backlog scope for this item.

## Current Understanding

- Root cause is still unresolved.
- Strong likelihood of preview temporal state ownership/race issues across:
  - compositor requests still in flight during clip switches
  - transition overlap between outgoing/incoming slots
  - timing of frame-history reset relative to transition start

## Exit Criteria

- No observable previous-clip bleed in preview across clip navigation and trim/start edits (with temporal effects active).
- Preview behavior matches export/render behavior for tested scenarios.

## Suggested Starting Points for Future Pass

- `Hypnograph/App/Main/Views/PlayerView.swift`
- `Hypnograph/App/Main/Views/PlayerContentView.swift`
- `HypnoPackages/HypnoCore/Renderer/Core/FrameCompositor.swift`
- `HypnoPackages/HypnoCore/Renderer/Display/RendererView.swift`
- `HypnoPackages/HypnoCore/Renderer/Effects/Core/EffectManager.swift`
