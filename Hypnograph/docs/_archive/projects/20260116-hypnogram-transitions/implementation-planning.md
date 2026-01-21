# Hypnogram Transitions (Preview + Live): Implementation Planning

**Created**: 2026-01-16  
**Status**: Draft

This plan aims to unify clip-boundary transitions across Preview and Live, with minimal disruption to the current render pipeline.

## Phase 0: Define settings + shared model

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

## Phase 1: Wire settings into Live (replace hardcoded crossfadeDuration)

Live already has the right architecture (A/B players). We want it to follow the shared setting:

- Replace `LivePlayer.crossfadeDuration` with the value from settings.
- Implement `style == .none`:
  - no animation, immediate switch to next player (still keep A/B infrastructure).
- Implement `style == .punk`:
  - keep A/B, but use a stepped/jittery alpha progression instead of a smooth easeInOut.

Acceptance:
- Live matches the chosen style.
- Crossfade still works exactly as before when style is `.crossfade`.

## Phase 2: Add the same transition mechanism to Preview

Preview (`PreviewPlayerView`) currently uses one `AVPlayerView` and replaces its item.

Goal: implement the same A/B approach as Live:
- Maintain two player views (A/B) stacked in the same container view.
- When a new composition is built, load it into the inactive player, start it, then transition to it using the chosen style.

Key points:
- Keep existing “build player item asynchronously” flow; only swap display once the new item is ready.
- Ensure still-image clips behave correctly (they don’t advance time via AVPlayer):
  - during transition, treat still clips as “paused on first frame” and transition visually only.

Acceptance:
- Preview transitions match Live transitions for the same style/duration.

## Phase 3: Establish a clip-boundary hook (foundation for Volume Leveling)

Introduce a small internal abstraction so both Preview and Live have a consistent boundary event:

- `willTransition(from:to:)`
- `didTransition(to:)`

This should be used to attach future audio behavior:
- boundary fades (always safe)
- volume leveling gain ramps (when leveling is enabled)

This phase is intentionally lightweight; it is a coordination hook, not a new audio engine.

## Phase 4: UX polish + defaults

- Add the transition controls to Player Settings:
  - Style picker (None / Crossfade / Punk)
  - Duration control (slider/stepper)
- Decide defaults:
  - Live default may remain Crossfade ~1.5s if that’s already tuned.
  - Preview default could be shorter (e.g. 0.15–0.35s), but v1 can keep one shared setting for simplicity.

Future (optional):
- Add a “Suppress in Preview” boolean if transitions feel disruptive while editing.

## Validation checklist

- Rapid left/right browsing doesn’t tear down players incorrectly (no black frames, no stuck alpha).
- Still-image clips transition cleanly (no timers fighting transitions).
- Live and Preview both honor the same setting.
- Watch mode auto-advance transitions consistently.

