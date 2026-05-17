---
doc-status: draft
---

# Smoother Playback

## Overview

Hypnograph preview playback can look subtly jumpier than Apple Photos when playing a normal iPhone video as a single-layer composition at 100% speed.

This spike is about finding the source of that stutter without changing Hypnograph's core architecture or adding a special case for single-layer videos. Playback smoothness is a reliability issue for the product because the player is the live visual instrument's primary surface.

What we learned from the April 25, 2026 investigation:

- The test hypnogram had one composition, one external Apple Photos video layer, no active effects, `playRate` 1.0, and a 16.69s clip window from a 21.1s source.
- Before the investigation, preview configured `frameRate: 30` but also `useSourceFrameRate: true`, so 30fps was a fallback rather than a strict forced cadence.
- Runtime diagnostics showed active playback at roughly 14-15 delivered frames per second on the source-derived cadence path, with occasional 100ms source presentation timestamp gaps.
- Forcing the preview build to ignore source-derived frame rate improved the observed cadence to roughly 19-26 delivered frames per second, but still did not reach the expected 30fps source cadence or 60Hz display redraw cadence.
- In the improved run, `drawFPS` and `newFPS` were nearly equal, suggesting the display/render loop itself was only completing around 20-25 draw cycles per second rather than drawing at 60Hz and reusing frames between 30fps source frames.
- This points to at least two possible issues: source-frame-rate selection may be choosing a poor cadence for some iPhone/Photos assets, and the custom compositor / `AVPlayerItemVideoOutput` / Metal presentation path may be too slow or blocking under normal preview conditions.

## Scope

- MUST preserve the general compositor-based preview architecture during the spike.
- MUST avoid special-casing single-layer video playback as the first fix.
- MUST distinguish source cadence selection problems from compositor/render-throughput problems.
- SHOULD keep diagnostics disabled by default or local to the spike.
- SHOULD test against the same real Apple Photos video that exposed the problem.
- SHOULD compare measured frame cadence with the perceived playback result.
- MAY add temporary instrumentation, but it should be easy to remove.
- MUST NOT keep throwaway diagnostic code or experimental playback switches without a follow-up decision.

## Plan

- Smallest meaningful next slice:
  Add a clean, temporary frame-cadence diagnostic that records active playback only and can be read from a local file without relying on Xcode console output.

- Immediate acceptance check:
  For the known test video, capture active playback windows that report draw cadence, new-buffer cadence, maximum draw gaps, maximum source presentation timestamp gaps, player time, playback rate, and time control status.

- Candidate probes:
  1. Run the baseline source-derived cadence path and record measured cadence.
  2. Run a fixed 30fps preview-cadence path and record whether cadence improves.
  3. Disable the preview framing hook and record whether cadence approaches 30fps source / 60Hz display expectations.
  4. If framing is not the bottleneck, instrument `FrameCompositor` render duration and `AVPlayerItemVideoOutput` frame availability separately.
  5. Inspect the source asset's real track metadata, especially nominal frame rate, minimum frame duration, time scale, and whether the Photos-provided asset appears variable-frame-rate or proxy-like.

## Open Questions

- Is the source-derived frame-rate path choosing 15fps or another low cadence for this Photos asset?
- Is `HumanCenteringFramingHook` or another source-framing step doing expensive work during playback?
- Is `FrameCompositor` blocking AVFoundation enough to reduce delivery cadence?
- Does `AVPlayerItemVideoOutput` behave differently from Apple Photos' native presentation path for this asset?
- What cadence does export produce for the same hypnogram, and does the exported file look smooth?
