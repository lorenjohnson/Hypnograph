---
doc-status: draft
---

# New Compositions Advanced Source Selection

## Overview

This project is about adding two advanced source-selection options to the `New Compositions` panel so random composition generation can be constrained a little more intentionally without complicating the default surface.

The two options are:

1. a source-length requirement so a chosen source must be at least as long as the chosen composition length
2. a start-point randomization toggle so a chosen clip starts at a random valid point within the source rather than always from the beginning

Both of these controls should live under an `Advanced` section at the bottom of the `New Compositions` panel. That section may eventually be feature-flagged or hidden by default, but for now the goal is just to capture the design and naming clearly before implementation.

The current behavior is partly implicit. Hypnograph already tends to choose random clip offsets when generating from longer media, but that behavior is not clearly surfaced as a user-facing setting. Source-length suitability is also not currently expressed as a direct option in the panel, even though it materially affects how generation feels.

This may also be a good moment to clean up adjacent logic in the same area, especially if the implementation work already touches the `New Compositions` settings model and generation path.

## Rules

- MUST keep these options scoped to future composition generation only.
- MUST place both options in an `Advanced` section at the bottom of the `New Compositions` panel.
- MUST propose and settle on clear user-facing names before implementation.
- SHOULD keep the controls simple booleans unless implementation proves a richer shape is truly needed.
- SHOULD preserve the current fast, low-friction feel of `New Compositions` for users who never touch the advanced options.
- MAY feature-flag or hide the `Advanced` section later if that proves useful.

## Proposed Setting Names

Recommended names:

1. `Require Full-Length Sources`
   - meaning: chosen sources must be at least as long as the chosen composition length
2. `Randomize Start Point`
   - meaning: when possible, start a chosen clip from a random valid point within the source
   - default: `true`

Alternative names worth keeping in mind:

- `Only Use Sources Long Enough`
- `Require Sources to Cover Composition Length`
- `Start at Random Point`
- `Start Clip at Random Point`

Current recommendation is to favor the shorter, more legible pair:

- `Require Full-Length Sources`
- `Randomize Start Point`

## Plan

- Smallest meaningful next slice: decide the final user-facing names and write down the exact intended generation behavior for each option.
- Immediate acceptance check: the project clearly states what each setting means, where it lives in the UI, and which one defaults to `true`.
- Follow-on slice: define how these options interact with still images, very short video sources, and the existing composition-length range behavior.

## Possible Adjacent Cleanup

- normalize the internal setting names for the whole `New Compositions` area, even if the user-facing labels stay as they are
- investigate why transitions sometimes do not run between compositions and instead cut directly to the next composition
- consider whether holding `1–9` should temporarily bypass the selected layer's effect chain as well as the composition/global chain, instead of only bypassing the global chain

## Open Questions

- Should the source-length requirement apply only to video clips, or should still images be treated as always eligible?
- If `Require Full-Length Sources` is on and the pool is too constrained, should generation fall back gracefully or fail visibly?
- Should `Randomize Start Point` be ignored for sources that are only just long enough, or should it still try to vary within any valid remainder?
- When the `Advanced` section is eventually feature-flagged or hidden, what is the cleanest place for these settings to live in Debug or power-user builds?
- If internal setting names are normalized here, what is the cleanest migration path for existing saved settings?
- Is the intermittent transition skip actually related to composition generation state, or is it a separate playback/transition bug that only happens to surface nearby?
- Would bypassing both global and layer effects during `1–9` hold make solo preview more legible, or would it remove too much of the actual look the user is trying to inspect?
