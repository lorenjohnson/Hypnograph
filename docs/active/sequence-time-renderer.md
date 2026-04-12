---
doc-status: in-progress
---

# Overview

This project is the first architectural pass toward a mature render pipeline that can eventually drive both preview and export from the same sequence-time model.

The immediate goal is not to replace the current AVPlayer-based preview path in one sweep. The immediate goal is to introduce a canonical forward sequence-time plan that can answer:

- what composition is active at sequence time `T`
- whether `T` is in a composition body or a transition overlap
- what outgoing and incoming composition times should be sampled during that overlap

That shared time model is the prerequisite for later work such as full-sequence render, deterministic export, playhead/scrubbing, and a preview path that is less dependent on stitched `AVPlayerItem` handoffs.

# Scope

- MUST define a canonical forward sequence-time plan for a saved hypnogram.
- MUST resolve composition-owned vs hypnogram-default transition settings into that plan.
- MUST model transition overlap as sequence time, not as a player-side side effect.
- SHOULD keep the first slice small and usable by future preview and export work without replacing the current playback engine yet.
- MUST NOT attempt a full preview-pipeline rewrite in this project’s first pass.

# Plan

- Smallest meaningful next slice:
  - add a tested `SequenceRenderPlan` that maps global sequence time into composition body or transition overlap samples
  - make transition duration clamping and overlap math explicit and reusable
  - add an export-shaped frame schedule so a future sequence renderer can iterate deterministic frame requests at a target frame rate
- Immediate acceptance check:
  - a multi-composition hypnogram can resolve sequence time deterministically
  - transition ownership and overlap reduce total rendered sequence duration as expected
  - the same plan can later feed both preview and export callers
  - export-oriented code can request ordered frame samples without inventing a second timing model
- Follow-on slices:
  - use the same plan to implement full-sequence render/export
  - add playhead-aware preview/scrubbing on top of that sequence-time model

# Open Questions

- Whether the first consumer after planning should be full-sequence export or a playhead/scrubbing path.
- How much of the current AVPlayer preview path should be preserved as a pragmatic transport shell while a shared sequence renderer grows underneath it.
- When audio enters the same shared timeline model versus remaining partly delegated to AVFoundation for a while.
