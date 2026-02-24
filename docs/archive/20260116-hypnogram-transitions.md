# Hypnogram Transitions (Preview + Live)

**Created**: 2026-01-16
**Status**: Implemented (superseded by Metal playback pipeline)
**Depends on**: [Unified Player Architecture](20260116-unified-player-architecture.md)

## Overview

Goal: add a **player/render setting** that controls how we visually (and eventually sonically) transition **between hypnograms** when:

- stepping through clip history (left/right),
- generating a new hypnogram,
- auto-advancing in watch mode,
- sending a hypnogram to Live.

This setting should apply to both **Preview** and **Live**. A future option may allow suppressing transitions in Preview, but that is out of scope for v1 unless it proves necessary.

## Current behavior (as of 2026-01-20)

- **Preview**: uses `PlayerContentView` + `PlayerView` (`MTKView`) with shader-based transitions between textures.
- **Live**: uses the same Metal surface + shader transition path as Preview.

## Do we need "two players" in Preview?

Not necessarily.

True crossfade between two different hypnograms requires overlapping playback, which is simplest with two players. However, Preview has special behaviors (scrubbing, source selection overlays, debug affordances) where a single-player architecture is convenient.

For v1, Preview transitions can be implemented without a second player by:

- capturing the last rendered frame (or taking a view snapshot),
- swapping the `AVPlayerItem`,
- fading the captured frame out while the new playback fades in underneath.

This yields a smooth visual transition and gives us the "boundary hook" for audio fades/leveling, while avoiding a large preview refactor.

## Why do this now

Transitions make browsing and performance more watchable:

- reduced perceptual harshness of hard cuts,
- better continuity when stepping through history,
- creates a natural "boundary hook" we can later use for **audio smoothing** and **volume leveling**.

## Proposed setting (v1)

Add a setting that selects between 2–3 transition types and a duration:

- `Transition Style`
  - **None** (hard cut)
  - **Crossfade** (A/B crossfade)
  - **Punk** (a stylized crossfade: flicker/jitter/dissolve feel; details below)
- `Transition Duration` (e.g. 0.15–1.5 seconds; default TBD)

Notes:

- For Live, we already have a crossfade duration; this becomes the user-facing source of truth.
- For Preview, we can implement the same styles without requiring A/B players (using a snapshot overlay). If later we want "true crossfade parity", we can migrate Preview to A/B.

## Transition style definitions

### None

Hard cut to the next hypnogram (current behavior in Preview).

### Crossfade

Blend old hypnogram out while new hypnogram fades in over duration.

### Punk (v1-friendly definition)

A "degraded" crossfade that feels more energetic than a smooth fade, without requiring a full video shader pipeline:

- same A/B players as Crossfade
- but alpha progression is **non-linear and/or jittered** (e.g. stepped keyframes, brief flickers, hold-and-snap)

This keeps implementation close to existing Live crossfade infrastructure and avoids reintroducing a renderer-side transition system prematurely.

## Relationship to Volume Leveling

Most perceived audio spikes happen at the clip boundary. If we unify "clip boundary transitions" across Preview/Live, we gain a single, stable hook point to:

- fade audio at boundaries (cheap win even with leveling Off),
- ramp leveling gain between hypnograms (avoid sudden gain jumps),
- later apply peak protection logic around boundaries.

This transitions project can be treated as foundational work for the "Volume Leveling" project.

---

## Implementation Plan

This plan aims to unify clip-boundary transitions across Preview and Live, with minimal disruption to the current render pipeline.

### Phase 0: Define settings + shared model

Add a shared model type (location TBD, likely app layer first):

- `HypnogramTransitionStyle`
  - `.none`
  - `.crossfade`
  - `.punk`
- `HypnogramTransitionSettings`
  - `style`
  - `durationSeconds`
  - (future) `suppressInPreview`

Add to `Settings` so it is persisted and used by both Preview and Live.

### Phase 1: Wire settings into Live (replace hardcoded crossfadeDuration)

Live already has the right architecture (A/B players). We want it to follow the shared setting:

- Replace `LivePlayer.crossfadeDuration` with the value from settings.
- Implement `style == .none`:
  - no animation, immediate switch to next player (still keep A/B infrastructure).
- Implement `style == .punk`:
  - keep A/B, but use a stepped/jittery alpha progression instead of a smooth easeInOut.

Acceptance:
- Live matches the chosen style.
- Crossfade still works exactly as before when style is `.crossfade`.

### Phase 2: Add the same transition mechanism to Preview

Preview (`PreviewPlayerView`) currently uses one `AVPlayerView` and replaces its item.

Goal: implement the same A/B approach as Live:
- Maintain two player views (A/B) stacked in the same container view.
- When a new composition is built, load it into the inactive player, start it, then transition to it using the chosen style.

Key points:
- Keep existing "build player item asynchronously" flow; only swap display once the new item is ready.
- Ensure still-image clips behave correctly (they don't advance time via AVPlayer):
  - during transition, treat still clips as "paused on first frame" and transition visually only.

Acceptance:
- Preview transitions match Live transitions for the same style/duration.

### Phase 3: Establish a clip-boundary hook (foundation for Volume Leveling)

Introduce a small internal abstraction so both Preview and Live have a consistent boundary event:

- `willTransition(from:to:)`
- `didTransition(to:)`

This should be used to attach future audio behavior:
- boundary fades (always safe)
- volume leveling gain ramps (when leveling is enabled)

This phase is intentionally lightweight; it is a coordination hook, not a new audio engine.

### Phase 4: UX polish + defaults

- Add the transition controls to Player Settings:
  - Style picker (None / Crossfade / Punk)
  - Duration control (slider/stepper)
- Decide defaults:
  - Live default may remain Crossfade ~1.5s if that's already tuned.
  - Preview default could be shorter (e.g. 0.15–0.35s), but v1 can keep one shared setting for simplicity.

Future (optional):
- Add a "Suppress in Preview" boolean if transitions feel disruptive while editing.

## Validation checklist

- Rapid left/right browsing doesn't tear down players incorrectly (no black frames, no stuck alpha).
- Still-image clips transition cleanly (no timers fighting transitions).
- Live and Preview both honor the same setting.
- Watch mode auto-advance transitions consistently.
