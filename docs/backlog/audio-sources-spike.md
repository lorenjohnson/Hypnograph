---
doc-status: draft
---

# Audio Sources Spike

## Overview

This spike is about exploring whether Hypnograph should support audio files as source layers inside compositions.

The most concrete first version is not about generation. It is about allowing the user to add an audio file from disk as a layer alongside image and video layers, show that layer clearly as audio in the composition UI, and let the user work with its timing/range inside the composition much like other media. Ideally that would include waveform display in the timeline so the user can meaningfully choose which portion of the audio plays during the composition.

There is also a broader question in the background about whether audio sources should eventually participate in generation workflows, but that is secondary here. The first goal is to determine whether audio-as-layer is coherent, feasible, and valuable enough on its own to pursue now.

## Rules

- MUST treat this as a spike, not a commitment to ship audio support.
- MUST keep the first question focused on audio files as manually added composition layers.
- MUST NOT let the first pass expand into a full audio-generation system unless that becomes clearly necessary.
- SHOULD treat waveform/timeline representation as part of the evaluation, not just file import.
- SHOULD keep the resulting behavior legible in the existing composition UI if implementation is attempted.

## Plan

- Smallest meaningful next slice: trace what would have to change for the existing "add layer from disk" path to accept supported audio file types.
- Immediate acceptance check: determine whether audio can fit the current layer/timeline model cleanly enough to justify implementation.
- Follow-on slice: if it looks promising, decide what the minimum useful audio-layer UX would be:
  - icon-only representation
  - range selection
  - waveform display
  - composition-level vs layer-level editing behavior

## Open Questions

- Does audio belong naturally as just another layer type in the current composition model?
- What minimum set of file types should count as supported in a first pass?
- Is waveform generation lightweight enough to be part of an initial implementation, or should that come later?
- Would audio layers immediately imply changes to export, playback, or sequencing expectations that make the first pass larger than it appears?
- Is the right first outcome here a small implementation, or a decision to defer audio until sequences or timeline work is further along?
