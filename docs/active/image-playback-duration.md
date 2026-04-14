---
doc-status: in-progress
---

# Image Playback Duration

## Overview

Still images already have an explicit timed-media model in the core recipe and renderer layers, but preview playback remains unreliable enough that this project is not done.

The current codebase already treats stills as timed clips:
- image layers carry duration through `MediaClip.duration`
- image sources created from files, Photos, and random selection all receive clip lengths
- composition duration resolves from the longest layer clip
- renderer and export already accept timed still-image clips as first-class inputs

The remaining problem is the preview player. We made real progress on still-image-only playback, especially for simple cases, but the special handling in preview is still flaky enough that it cannot merge as-is. In particular, transitions other than `None` and some pause/resume or composition-switching paths can still push preview into an indeterminate state.

## Rules

- MUST keep still-image timing explicit through `MediaClip.duration` rather than relying on implicit or effectively infinite playback.
- MUST keep image-only compositions advancing correctly once their timed duration completes.
- MUST preserve mixed-media support, so images and videos can still coexist in the same composition model.
- MUST continue treating still-image playback length as separate from video in/out points.
- SHOULD keep still-image special handling as locally contained as possible, preferably inside preview-player behavior rather than spread across unrelated playback code.
- SHOULD keep random image selection aligned with composition-length constraints and the existing clip-length request path.
- MUST NOT introduce a second duration model for still images unless a real product need emerges that the current `MediaClip.duration` model cannot satisfy.

## Progress

- Confirmed that the core model was already in place:
  - image clip creation from files and Photos sets explicit duration
  - image duration editing already flows through `setLayerRange`
  - composition duration already resolves from layer durations
  - render and export tests already support still-image clips
- Improved preview playback behavior enough to make some cases work:
  - single still-image compositions can now play
  - multi-still compositions improved
  - some still-image handoff cases now work where they previously froze immediately
- Added preview-player-side special handling experiments:
  - explicit first-frame priming for still-image compositions
  - preview-owned timing for still-image duration/end behavior
  - pause/resume refresh sequencing

## Current Problems

- Still-image preview playback is still flaky in some cases.
- Pause/resume paths can still leave still-image playback in a bad state.
- Transition styles other than `None` appear especially unstable with still-image compositions.
- Once preview gets into a bad state, switching back to video compositions can sometimes show black output until enough composition switching “clears” the state.
- The still-image handling added so far may now be interfering with normal video/transition playback, which suggests the preview-specific special handling needs to be simplified and more tightly contained.

## Next Direction

The most likely next step is not to keep layering fixes onto the current behavior. It is to contain still-image preview handling more deliberately inside the preview player path and reduce how much it leaks into the ordinary video playback/transition path.

That unfinished code is being parked on branch:

- `project/image-playback-duration`

## Open Questions

- What is the smallest preview-player architecture that lets still-image compositions behave like timed media without destabilizing video playback or transitions?
- Should still-image preview timing be owned entirely by `PlayerView`, or should the lower-level display/player pipeline itself become more aware of timed still playback?
- Do we need a clearer split between “prime a still frame for display” and “advance timed composition playback” so those responsibilities stop overlapping awkwardly?
