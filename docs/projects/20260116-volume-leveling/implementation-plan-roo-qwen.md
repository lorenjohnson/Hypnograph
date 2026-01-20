# Volume Leveling (Player Settings): Implementation Planning

**Created**: 2026-01-20  
**Status**: Draft

This plan focuses on "volume leveling across hypnograms" while keeping the codebase simple and user volume controls predictable.

## Phase 0: Decide the leveling policy

1) **What audio are we leveling?**
   - Level the **whole hypnogram output** (one gain value applied uniformly to the mix).
   - **MVP**: RMS-based leveling only (no future modes needed yet).

2) **Where does audio mixing happen?**
   - Ensure Preview and Export apply the same mixing policy:
     - `CompositionBuilder` already constructs an `AVMutableAudioMix` for multi-track cases.
     - `RenderEngine.makePlayerItem` should attach the `audioMix` to the returned `AVPlayerItem`.

## Phase 0.5: Clip-boundary hook

- Apply audio smoothing at clip boundaries using a **150-300ms fade**.
- This is critical for preventing perceived volume spikes during clip transitions.

## Phase 1: Settings + UI surface

### Settings model
Add fields to `Settings`:
- `volumeLevelingEnabled: Bool` (default `true`)
- **No UI toggle yet** - feature is enabled by default and saved to settings
- **No user-adjustable target** - RMS target is fixed (e.g., -16 dBFS) for MVP

### Player Settings UI
- **No UI changes needed** - feature is enabled by default
- Future: Add toggle when needed (plumbing is in place)

## Phase 2: Audio analysis (RMS MVP)

- Analyze **per clip** (not composition) using first 5-10 seconds of audio
- Compute RMS for each clip's audio track
- Cache results keyed by clip ID (e.g., `clipId: String`)
- Skip analysis for audioless clips (gain = 1.0)
- **Fixed target**: RMS normalized to -16 dBFS (no user adjustment)

## Phase 3: Apply gain consistently

- **Preview**: Apply via `AVMutableAudioMix` (preferred)
- **Export**: Extend `CompositionBuilder` to incorporate leveling gain
- **Live**: Default off (add toggle later after validation)
- Implement boundary smoothing using `AVMutableAudioMix` ramping

## Phase 4: Performance + caching

- Cache analysis results to avoid repeated processing
- Fallback to gain = 1.0 on analysis failure
- **Per-clip normalization**: Each clip is normalized to target RMS before playback

## Validation checklist

- [ ] Browsing clip history: volume doesn't jump between clips
- [ ] Exported videos match preview loudness
- [ ] No audible pumping during clip changes
- [ ] Multi-layer clips maintain consistent volume
- [ ] Audioless clips unaffected (gain = 1.0)
- [ ] Final output meets target RMS (-16 dBFS) when played sequentially