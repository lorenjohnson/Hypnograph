# Volume Leveling (Player Settings): Implementation Planning

**Created**: 2026-01-16  
**Status**: Draft

This plan focuses on “volume leveling across hypnograms” while keeping the codebase simple and keeping user volume controls predictable.

## Phase 0: Decide the leveling policy (small but important)

Make two explicit choices so implementation stays coherent:

1) **What audio are we leveling?**
- v1: level the **whole hypnogram output** (one gain value applied uniformly to the mix).

2) **Where does audio mixing happen?**
- Ensure Preview and Export apply the same mixing policy:
  - `CompositionBuilder` already constructs an `AVMutableAudioMix` for multi-track cases.
  - `RenderEngine.makePlayerItem` should attach the `audioMix` to the returned `AVPlayerItem` (today export uses it, preview does not).

Outcome: preview and export stop diverging as we evolve audio behavior.

## Phase 0.5: Identify the clip-boundary hook (pairs with video transitions)

We want clip-to-clip audio to feel smooth. There are two places we can hook this:

- **Today (no transitions yet):** when `Dream` advances clips (left/right or watch mode), we can apply an audio fade-out/fade-in and/or a short gain ramp.
- **After a “video transitions between clips” feature exists:** use the transition boundary itself as the unified hook to apply audio smoothing alongside the visual transition.

This is important because most perceived “spikes” happen right at the boundary.

Related project: `docs/projects/20260116-hypnogram-transitions/overview.md`.

## Phase 1: Settings + UI surface

Add a user-facing setting that is easy to understand and safe by default.

### Settings model
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
- (optional) `smoothAudioAtClipChanges`: bool (default true once we’re confident)

### Player Settings UI
Add a “Volume Leveling” row in `PlayerSettingsView` under Audio:
- Toggle: “Leveling”
- Mode picker: Off / RMS (later LUFS)
- Optional: advanced popover or disclosure for target and clamps

UX notes:
- Keep the existing Preview/Live volume sliders unchanged.
- Leveling should be visible (a small “LVL” indicator in HUD later is optional).

## Phase 2: Audio analysis (RMS MVP)

We need a way to estimate loudness for a hypnogram clip.

### Minimal algorithm (MVP)
- Read PCM samples from an audio track and compute RMS over a bounded window.
- Convert measured RMS to a gain multiplier to approach target.
- Clamp gain within configured limits.

Key constraints:
- Must be fast enough for browsing clip history.
- Must not block the UI.

### Where to analyze
Prefer analyzing the *actual built composition* for correctness:
- Build composition as we already do for preview/export.
- Run analysis on the resulting `AVAsset` (composition) so loops/time ranges match the clip.

But this can be expensive, so start with a pragmatic compromise:
- Analyze only the first N seconds (e.g. 5–10s) of the composition’s audio.
- Cache results keyed by a stable clip identifier (e.g. clip id) and invalidate when sources change.

### Implementation sketch (module placement)
- New type in `HypnoCore` (or app layer if preferred):
  - `AudioLevelAnalyzer`
    - `func measureRMS(asset: AVAsset, duration: CMTime) async -> Float`
    - `func recommendedGain(measured: Float, target: Float) -> Float`
- Use `AVAssetReader` + `AVAssetReaderTrackOutput` to pull linear PCM.

## Phase 3: Apply gain consistently (Preview + Live + Export)

We apply *one gain per hypnogram* without changing internal layer balance.

### Preview
Two viable integration points:

1) **Via `AVPlayerItem.audioMix` (preferred)**
- Multiply each input track’s volume by the same global gain.
- Keeps logic close to the render pipeline and matches export.

2) **Via `AVPlayer.volume` multiplier**
- Effective output volume = `userVolume * levelingGain`
- Simple, but only affects preview/live playback and not export.

Recommended: use audioMix for correctness + export parity; optionally also keep a player.volume multiplier for fast prototyping, but converge on audioMix.

Also: add **boundary smoothing** so changes are not abrupt (Option 5 from the overview):
- Fade-out old item and fade-in new item over `volumeLevelingSmoothingMs`.
- If using `audioMix`, schedule a short volume ramp on each `AVMutableAudioMixInputParameters` around the boundary.
- If using `player.volume`, do a small `Timer`/task-driven ramp (preview-only) as a prototype.

### Export
- `RenderEngine.export` already assigns `exportSession.audioMix = build.audioMix`.
- Extend `CompositionBuilder` to incorporate the leveling gain into `build.audioMix`.

### Live
Live uses its own player routing. Decide whether leveling applies:
- v1: default off for Live (avoid unexpected behavior on stage).
- Provide an explicit toggle later after validation.

## Phase 4: Performance + caching

Add a cache to avoid repeated analysis:
- Key: clip id (or a hash of sources + start times + duration + playRate).
- Value: measured loudness + recommended gain + timestamp.

Heuristics:
- If clip has no audio tracks, skip analysis and use gain = 1.0.
- If analysis fails, fall back to gain = 1.0.

## Phase 5: Quality upgrades (optional follow-ons)

If RMS leveling is “close but not great”, evolve toward:

- LUFS measurement mode (integrated loudness with gating).
- Optional limiter/peak protection (normalize + protect peaks). Real-time may require a custom pipeline; offline/cache is a viable path.
- Optional within-clip gain envelopes (windowed analysis + smoothed ramps) if needed.
- “Audio policy” controls:
  - “Mix all layers”
  - “Use layer 1 only”
  - “Use selected layer”

## Validation checklist

- Browsing clip history: volume doesn’t jump wildly when stepping left/right.
- Exported videos match preview loudness behavior (within reason).
- No audible pumping/jitter when rapidly switching clips (smoothing works).
- Multi-layer clips don’t clip worse than before (track attenuation + clamp).
- Clips with no audio are unaffected.
