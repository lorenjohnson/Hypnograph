# Video Playback Stall (Audio Continues)

**Created**: 2026-01-27  
**Status**: Backlog

> **2026-02-15 note:** On the current build run directly from Xcode, this issue is not currently reproducible. Keeping this project in backlog until a reliable repro returns.

## Summary

Sometimes during normal editing/playback (especially around transitions / rapid edits), **video freezes or blanks** while **audio continues**. Navigating clip history backward/forward often “unsticks” video. Waiting can also recover.

We currently have **two mitigations** in code:

1. **Honor compositor cancellations** so we don’t build a backlog of stale render requests:
   - `HypnoCore/Renderer/Core/FrameCompositor.swift`
2. **TODO: Stall recovery** in the Metal display pipeline by reattaching `AVPlayerItemVideoOutput` if it stops producing pixel buffers while playing:
   - `HypnoCore/Renderer/FrameSource/AVPlayerFrameSource.swift`

The stall recovery avoids long freezes, but can cause **brief black/blank frames** when it reattaches.

Goal of this project: **identify and fix the root cause** so we can remove the TODO recovery path (or make it unnecessary/invisible).

## Observed Logs

Around failures we see AVFoundation internal errors such as:

- `<<<< VRP >>>> signalled err=-12852`
- `<<<< CustomVideoCompositor >>>> signalled err=-12784`
- `<<<< CustomVideoCompositor >>>> signalled err=-12504`
- `<<<< FigFilePlayer >>>> signalled err=-12860`

## Hypotheses (to test)

- AVFoundation pipeline stall triggered by rapid `AVPlayerItem` swaps during transitions.
- Video compositor request backlog / cancellation not honored (partially addressed).
- `AVPlayerItemVideoOutput` host-time mapping gets “stuck” temporarily (workaround reattaches output).
- Composition changes that affect video composition / instruction objects cause internal invalidation.

## Suggested Investigation Plan

- Add a lightweight, throttled debug counter/log when stall recovery triggers (and when it reattaches).
- Confirm whether stalls correlate with:
  - transition start / completion
  - rapid effect changes (effectsChangeCounter)
  - seeking / clip-history navigation while playing
- Reduce the reproduction to a minimal sequence of:
  - play → transition → edit param → transition → etc.
- Evaluate if we can avoid pixel-buffer starvation by:
  - not detaching/reattaching outputs (root fix)
  - adjusting `AVVideoCompositing` cancellation/queueing strategy
  - ensuring transitions don’t start until both sources have a frame (already partially done)

## Exit Criteria

- No visible blank/black frames during normal editing and transitions.
- No “video frozen but audio continues” reports during extended self-testing.
- Remove or gate the TODO stall recovery code (or prove it is harmless/invisible).
