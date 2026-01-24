# Volume Leveling (Player Settings)

**Created**: 2026-01-16
**Status**: Proposal / Planning
**Depends on**: [Metal Playback Pipeline](../archive/20260117-metal-playback-pipeline/overview.md) (for boundary hooks)

## Overview

Goal: add an optional **Volume Leveling** feature that makes audio loudness feel **more consistent across hypnograms** while you browse (Preview) and perform (Live), without destroying creative dynamics within a single hypnogram.

This project is intentionally scoped to "leveling" (normalization and safety), not a full audio mixing/effects system.

### Problem

Hypnograms are assembled from arbitrary sources (videos with wildly different loudness). As the user steps through clip history, perceived volume can jump:
- quiet sources become inaudible without turning up volume,
- loud sources become unpleasant or clip.

Users want a setting that keeps perceived loudness "in the same neighborhood" across the session.

### Current behavior (as of 2026-01-16)

- Preview and Live have user-controlled volume (`Settings.previewVolume`, `Settings.liveVolume`).
- Export uses an `AVMutableAudioMix` that currently reduces volume per track when multiple audio tracks exist (simple `1 / trackCount` mixing).
- Preview playback (`RenderEngine.makePlayerItem`) does not currently apply the built `audioMix` to the `AVPlayerItem`, so preview loudness behavior can diverge from export.

### UX goal

- Add a **Volume Leveling** option in **Player Settings** (applies to Preview; optionally Live).
- Maintain a clear separation:
  - "My volume knob" (user volume slider) stays user-controlled.
  - "Leveling" is an optional automatic multiplier applied on top.
- Avoid sudden jumps: changes should be smoothed/faded between hypnograms.

### Non-goals (for v1)

- A full audio effects rack (compressor, EQ, limiter UI, per-layer audio editing).
- Per-layer leveling that changes the balance between layers.
- Perfect LUFS compliance in every edge case (we can iterate toward it).

### Key design decision: what are we leveling?

We need to decide which loudness we target:

1) **Whole-hypnogram leveling (recommended)**
Compute one gain value per hypnogram and apply it uniformly to the resulting mix.
- Pros: preserves internal dynamics/relative balance between layers; matches "keep relative db same across shown hypnograms".
- Cons: if a hypnogram is inherently sparse or dense, perceived loudness can still vary.

2) **Per-source leveling (not recommended for v1)**
Compute gain per layer/source and normalize layers individually.
- Pros: can reduce "one loud layer dominates" cases.
- Cons: changes the creative balance inside a hypnogram; more complexity and more surprising UX.

### Options for how to level

#### Option 0 — Off (raw audio)
No automatic leveling; only the user volume slider applies.
- Pros: preserves original dynamics, zero risk/complexity.
- Cons: loudness jumps between clips remain.

#### Option 1 — Per-clip static gain (simple normalization)
Analyze each clip once and compute a single gain multiplier for the entire clip. Apply that gain when the clip plays.

Analysis metric choices:
- **Peak-based**: prevents clipping but is a poor proxy for perceived loudness.
- **RMS/average power**: good MVP, implementable with `AVAssetReader`.
- **LUFS / EBU R128-style**: best perceived consistency (best long-term).

Apply gain choices:
- Preferred: `AVPlayerItem.audioMix` (keeps preview/export aligned).
- Alternate: `AVPlayer.volume` multiplier (fast prototype, but preview/live only).

This option preserves intra-clip dynamics (quiet parts stay quiet; loud parts stay loud) while reducing clip-to-clip jumps.

#### Option 2 — Per-clip ramped gain (gentle within-clip leveling)
Analyze loudness in windows (e.g. 250–1000ms), build a smoothed gain envelope, and apply slow volume ramps over time.
- Pros: reduces within-clip loudness swings more than Option 1.
- Cons: more analysis/bookkeeping; risk of audible "pumping" if attack/release is too aggressive.

#### Option 3 — Static gain + peak protection (normalize + limiter)
Use Option 1 to match loudness, plus a limiter/peak protection stage to avoid overs after boosting.
- Pros: strong default UX; prevents nasty peaks/clipping after normalization.
- Cons: true real-time limiting is non-trivial if we stay purely in `AVPlayer` land; best done offline/cached or via a custom audio pipeline.

#### Option 4 — Compression / AGC-style leveling ("SoundSource vibe")
Apply a dynamics processor (compressor/AGC) to reduce dynamic range and keep everything consistently "present".
- Pros: most consistent perceived loudness, especially for high dynamic-range clips.
- Cons: can sound fatiguing; is a creative alteration; real-time integration tends to require an `AVAudioEngine`-style pipeline with A/V sync concerns.

#### Option 5 — Boundary smoothing only (fade/crossfade at transitions)
Add a short fade-out/fade-in (e.g. 100–300ms) at clip boundaries regardless of leveling mode (or crossfade if we overlap clips).
- Pros: very cheap perceptual win; reduces harshness of cuts even when leveling is Off.
- Cons: does not actually equalize loudness; crossfade requires overlap/queueing strategy.

### Recommended approach (phased)

- **Phase 1 (MVP)**: Option 1 (static gain) using **RMS** + conservative clamps, plus Option 5 boundary fades to soften clip changes.
- **Phase 2**: Upgrade the analysis metric toward **LUFS** (or add LUFS as an additional mode).
- **Phase 3**: Optional peak protection (Option 3) and/or gentle within-clip ramps (Option 2), based on user feedback.

### Suggested Player Settings mapping (UX)

User-facing modes that map cleanly to the above options:

1. **Off** → Option 0
2. **Match Loudness (Preserve Dynamics)** → Option 1 (RMS first; LUFS later)
3. **Match Loudness + Protect Peaks** → Option 3 (likely requires offline/cache or custom pipeline)
4. **Leveling (Compress)** → Option 4 (advanced; likely later)

Separate toggle (or later "Transition" setting integration):
- **Smooth Audio at Clip Changes** → Option 5

### Interaction with a "Sound Source" concept

The roadmap mentions prototyping via a "SoundSource" effect. There is no current audio effect pipeline, but we can interpret this need as:
- a policy for which layer contributes audio (mix all layers vs pick one layer),
- and/or a more explicit "audio mode" that pairs nicely with leveling.

For this project, treat "sound source selection" as a separate future enhancement unless it is required to ship a usable leveling MVP.

### Relationship to video transitions

We likely want a video transition option between clip changes to make browsing more watchable. When that lands, it becomes a natural place to hook:
- Option 5 boundary fades (audio + video together),
- and any leveling gain ramps around the boundary (avoid spikes when a new clip starts).

See also: `../archive/20260116-hypnogram-transitions/overview.md`.

---

## Implementation Plan

This plan focuses on "volume leveling across hypnograms" while keeping the codebase simple and keeping user volume controls predictable.

### Phase 0: Decide the leveling policy (small but important)

Make two explicit choices so implementation stays coherent:

1) **What audio are we leveling?**
- v1: level the **whole hypnogram output** (one gain value applied uniformly to the mix).

2) **Where does audio mixing happen?**
- Ensure Preview and Export apply the same mixing policy:
  - `CompositionBuilder` already constructs an `AVMutableAudioMix` for multi-track cases.
  - `RenderEngine.makePlayerItem` should attach the `audioMix` to the returned `AVPlayerItem` (today export uses it, preview does not).

Outcome: preview and export stop diverging as we evolve audio behavior.

### Phase 0.5: Identify the clip-boundary hook (pairs with video transitions)

We want clip-to-clip audio to feel smooth. There are two places we can hook this:

- **Today (no transitions yet):** when `Dream` advances clips (left/right or watch mode), we can apply an audio fade-out/fade-in and/or a short gain ramp.
- **After a "video transitions between clips" feature exists:** use the transition boundary itself as the unified hook to apply audio smoothing alongside the visual transition.

This is important because most perceived "spikes" happen right at the boundary.

Related project: `../archive/20260116-hypnogram-transitions/overview.md`.

### Phase 1: Settings + UI surface

Add a user-facing setting that is easy to understand and safe by default.

#### Settings model
Add fields to `Settings` (names TBD):
- `volumeLevelingMode`: enum
  - `.off`
  - `.matchRMS` (MVP)
  - (future) `.matchLUFS`
  - (future) `.compress`
- `volumeLevelingTarget`: float (mode-dependent)
  - RMS: target RMS (or target dBFS)
  - LUFS: target LUFS (e.g. -16)
- `volumeLevelingMaxGainDB`: clamp (e.g. +12 dB)
- `volumeLevelingMinGainDB`: clamp (e.g. -12 dB)
- `volumeLevelingSmoothingMs`: boundary smoothing window (e.g. 150–300ms)
- (optional) `applyVolumeLevelingToLive`: bool (default false until validated)
- (optional) `smoothAudioAtClipChanges`: bool (default true once we're confident)

#### Player Settings UI
Add a "Volume Leveling" row in `PlayerSettingsView` under Audio:
- Toggle: "Leveling"
- Mode picker: Off / RMS (later LUFS)
- Optional: advanced popover or disclosure for target and clamps

UX notes:
- Keep the existing Preview/Live volume sliders unchanged.
- Leveling should be visible (a small "LVL" indicator in HUD later is optional).

### Phase 2: Audio analysis (RMS MVP)

We need a way to estimate loudness for a hypnogram clip.

#### Minimal algorithm (MVP)
- Read PCM samples from an audio track and compute RMS over a bounded window.
- Convert measured RMS to a gain multiplier to approach target.
- Clamp gain within configured limits.

Key constraints:
- Must be fast enough for browsing clip history.
- Must not block the UI.

#### Where to analyze
Prefer analyzing the *actual built composition* for correctness:
- Build composition as we already do for preview/export.
- Run analysis on the resulting `AVAsset` (composition) so loops/time ranges match the clip.

But this can be expensive, so start with a pragmatic compromise:
- Analyze only the first N seconds (e.g. 5–10s) of the composition's audio.
- Cache results keyed by a stable clip identifier (e.g. clip id) and invalidate when sources change.

#### Implementation sketch (module placement)
- New type in `HypnoCore` (or app layer if preferred):
  - `AudioLevelAnalyzer`
    - `func measureRMS(asset: AVAsset, duration: CMTime) async -> Float`
    - `func recommendedGain(measured: Float, target: Float) -> Float`
- Use `AVAssetReader` + `AVAssetReaderTrackOutput` to pull linear PCM.

### Phase 3: Apply gain consistently (Preview + Live + Export)

We apply *one gain per hypnogram* without changing internal layer balance.

#### Preview
Two viable integration points:

1) **Via `AVPlayerItem.audioMix` (preferred)**
- Multiply each input track's volume by the same global gain.
- Keeps logic close to the render pipeline and matches export.

2) **Via `AVPlayer.volume` multiplier**
- Effective output volume = `userVolume * levelingGain`
- Simple, but only affects preview/live playback and not export.

Recommended: use audioMix for correctness + export parity; optionally also keep a player.volume multiplier for fast prototyping, but converge on audioMix.

Also: add **boundary smoothing** so changes are not abrupt (Option 5 from the overview):
- Fade-out old item and fade-in new item over `volumeLevelingSmoothingMs`.
- If using `audioMix`, schedule a short volume ramp on each `AVMutableAudioMixInputParameters` around the boundary.
- If using `player.volume`, do a small `Timer`/task-driven ramp (preview-only) as a prototype.

#### Export
- `RenderEngine.export` already assigns `exportSession.audioMix = build.audioMix`.
- Extend `CompositionBuilder` to incorporate the leveling gain into `build.audioMix`.

#### Live
Live uses its own player routing. Decide whether leveling applies:
- v1: default off for Live (avoid unexpected behavior on stage).
- Provide an explicit toggle later after validation.

### Phase 4: Performance + caching

Add a cache to avoid repeated analysis:
- Key: clip id (or a hash of sources + start times + duration + playRate).
- Value: measured loudness + recommended gain + timestamp.

Heuristics:
- If clip has no audio tracks, skip analysis and use gain = 1.0.
- If analysis fails, fall back to gain = 1.0.

### Phase 5: Quality upgrades (optional follow-ons)

If RMS leveling is "close but not great", evolve toward:

- LUFS measurement mode (integrated loudness with gating).
- Optional limiter/peak protection (normalize + protect peaks). Real-time may require a custom pipeline; offline/cache is a viable path.
- Optional within-clip gain envelopes (windowed analysis + smoothed ramps) if needed.
- "Audio policy" controls:
  - "Mix all layers"
  - "Use layer 1 only"
  - "Use selected layer"

### Validation checklist

- Browsing clip history: volume doesn't jump wildly when stepping left/right.
- Exported videos match preview loudness behavior (within reason).
- No audible pumping/jitter when rapidly switching clips (smoothing works).
- Multi-layer clips don't clip worse than before (track attenuation + clamp).
- Clips with no audio are unaffected.
