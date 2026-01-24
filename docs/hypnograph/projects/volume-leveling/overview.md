# Volume Leveling (Player Settings): Overview

**Created**: 2026-01-16
**Status**: Proposal / Planning
**Depends on**: [Metal Playback Pipeline](../../archive/20260117-metal-playback-pipeline/overview.md) (for boundary hooks)

Goal: add an optional **Volume Leveling** feature that makes audio loudness feel **more consistent across hypnograms** while you browse (Preview) and perform (Live), without destroying creative dynamics within a single hypnogram.

This project is intentionally scoped to “leveling” (normalization and safety), not a full audio mixing/effects system.

## Problem

Hypnograms are assembled from arbitrary sources (videos with wildly different loudness). As the user steps through clip history, perceived volume can jump:
- quiet sources become inaudible without turning up volume,
- loud sources become unpleasant or clip.

Users want a setting that keeps perceived loudness “in the same neighborhood” across the session.

## Current behavior (as of 2026-01-16)

- Preview and Live have user-controlled volume (`Settings.previewVolume`, `Settings.liveVolume`).
- Export uses an `AVMutableAudioMix` that currently reduces volume per track when multiple audio tracks exist (simple `1 / trackCount` mixing).
- Preview playback (`RenderEngine.makePlayerItem`) does not currently apply the built `audioMix` to the `AVPlayerItem`, so preview loudness behavior can diverge from export.

## UX goal

- Add a **Volume Leveling** option in **Player Settings** (applies to Preview; optionally Live).
- Maintain a clear separation:
  - “My volume knob” (user volume slider) stays user-controlled.
  - “Leveling” is an optional automatic multiplier applied on top.
- Avoid sudden jumps: changes should be smoothed/faded between hypnograms.

## Non-goals (for v1)

- A full audio effects rack (compressor, EQ, limiter UI, per-layer audio editing).
- Per-layer leveling that changes the balance between layers.
- Perfect LUFS compliance in every edge case (we can iterate toward it).

## Key design decision: what are we leveling?

We need to decide which loudness we target:

1) **Whole-hypnogram leveling (recommended)**  
Compute one gain value per hypnogram and apply it uniformly to the resulting mix.
- Pros: preserves internal dynamics/relative balance between layers; matches “keep relative db same across shown hypnograms”.
- Cons: if a hypnogram is inherently sparse or dense, perceived loudness can still vary.

2) **Per-source leveling (not recommended for v1)**  
Compute gain per layer/source and normalize layers individually.
- Pros: can reduce “one loud layer dominates” cases.
- Cons: changes the creative balance inside a hypnogram; more complexity and more surprising UX.

## Options for how to level

### Option 0 — Off (raw audio)
No automatic leveling; only the user volume slider applies.
- Pros: preserves original dynamics, zero risk/complexity.
- Cons: loudness jumps between clips remain.

### Option 1 — Per-clip static gain (simple normalization)
Analyze each clip once and compute a single gain multiplier for the entire clip. Apply that gain when the clip plays.

Analysis metric choices:
- **Peak-based**: prevents clipping but is a poor proxy for perceived loudness.
- **RMS/average power**: good MVP, implementable with `AVAssetReader`.
- **LUFS / EBU R128-style**: best perceived consistency (best long-term).

Apply gain choices:
- Preferred: `AVPlayerItem.audioMix` (keeps preview/export aligned).
- Alternate: `AVPlayer.volume` multiplier (fast prototype, but preview/live only).

This option preserves intra-clip dynamics (quiet parts stay quiet; loud parts stay loud) while reducing clip-to-clip jumps.

### Option 2 — Per-clip ramped gain (gentle within-clip leveling)
Analyze loudness in windows (e.g. 250–1000ms), build a smoothed gain envelope, and apply slow volume ramps over time.
- Pros: reduces within-clip loudness swings more than Option 1.
- Cons: more analysis/bookkeeping; risk of audible “pumping” if attack/release is too aggressive.

### Option 3 — Static gain + peak protection (normalize + limiter)
Use Option 1 to match loudness, plus a limiter/peak protection stage to avoid overs after boosting.
- Pros: strong default UX; prevents nasty peaks/clipping after normalization.
- Cons: true real-time limiting is non-trivial if we stay purely in `AVPlayer` land; best done offline/cached or via a custom audio pipeline.

### Option 4 — Compression / AGC-style leveling (“SoundSource vibe”)
Apply a dynamics processor (compressor/AGC) to reduce dynamic range and keep everything consistently “present”.
- Pros: most consistent perceived loudness, especially for high dynamic-range clips.
- Cons: can sound fatiguing; is a creative alteration; real-time integration tends to require an `AVAudioEngine`-style pipeline with A/V sync concerns.

### Option 5 — Boundary smoothing only (fade/crossfade at transitions)
Add a short fade-out/fade-in (e.g. 100–300ms) at clip boundaries regardless of leveling mode (or crossfade if we overlap clips).
- Pros: very cheap perceptual win; reduces harshness of cuts even when leveling is Off.
- Cons: does not actually equalize loudness; crossfade requires overlap/queueing strategy.

## Recommended approach (phased)

- **Phase 1 (MVP)**: Option 1 (static gain) using **RMS** + conservative clamps, plus Option 5 boundary fades to soften clip changes.
- **Phase 2**: Upgrade the analysis metric toward **LUFS** (or add LUFS as an additional mode).
- **Phase 3**: Optional peak protection (Option 3) and/or gentle within-clip ramps (Option 2), based on user feedback.

## Suggested Player Settings mapping (UX)

User-facing modes that map cleanly to the above options:

1. **Off** → Option 0
2. **Match Loudness (Preserve Dynamics)** → Option 1 (RMS first; LUFS later)
3. **Match Loudness + Protect Peaks** → Option 3 (likely requires offline/cache or custom pipeline)
4. **Leveling (Compress)** → Option 4 (advanced; likely later)

Separate toggle (or later “Transition” setting integration):
- **Smooth Audio at Clip Changes** → Option 5

## Interaction with a “Sound Source” concept

The roadmap mentions prototyping via a “SoundSource” effect. There is no current audio effect pipeline, but we can interpret this need as:
- a policy for which layer contributes audio (mix all layers vs pick one layer),
- and/or a more explicit “audio mode” that pairs nicely with leveling.

For this project, treat “sound source selection” as a separate future enhancement unless it is required to ship a usable leveling MVP.

## Relationship to video transitions

We likely want a video transition option between clip changes to make browsing more watchable. When that lands, it becomes a natural place to hook:
- Option 5 boundary fades (audio + video together),
- and any leveling gain ramps around the boundary (avoid spikes when a new clip starts).

See also: `../../archive/20260116-hypnogram-transitions/overview.md`.
