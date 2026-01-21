# Hypnogram Transitions (Preview + Live): Overview

**Created**: 2026-01-16
**Status**: Implemented (superseded by Metal playback pipeline)
**Depends on**: [Unified Player Architecture](../20260116-unified-player-architecture/overview.md)

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
