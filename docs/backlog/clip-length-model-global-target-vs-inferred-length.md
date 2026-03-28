---
doc-status: draft
---

# Clip Length Model: Global Target vs Inferred Length

## Overview

This is a model and UX spike about what `Clip Length` should really mean. Right now there is an explicit global `targetDuration`, but in actual composition use there is also a strong mental model that the effective length of a hypnogram should simply come from the longest active layer.

That tension shows up in the UI today. In the right sidebar Global section, changing `Clip Length` updates the global target duration, but with multiple layers, extending global clip length does not automatically extend each layer's selected clip window. So users can end up doing duplicate work: first increasing global length, then separately extending layer trims to make the composition actually use that length.

The question is not only about one control. `targetDuration` currently appears to be carrying several responsibilities at once: it acts as the visible global clip length, it affects random clip generation and preferred source slice length, it caps layer trim UI in some paths, and it is also used by composition and export as playback duration authority. That means this spike should determine whether those responsibilities really belong to one value or whether they need to be separated.

The likely decision space is:

- keep explicit global clip length as the main model and make the UI clearer about it
- infer effective length from the longest active layer and reduce or remove the separate global control
- split the current combined model into more than one concept, for example generation length versus effective playback length

This should stay a spike for now. The goal is to leave behind a clearer question, a preferred direction, and a next prototype or implementation slice rather than rushing straight into a behavior change.

## Rules

- MUST clarify what responsibilities currently belong to `targetDuration` and which of them should stay coupled.
- MUST decide whether clip length should remain an explicit global value, become a derived value, or split into separate concepts.
- MUST account for generation, editing, playback, history, and export semantics rather than solving only the sidebar control in isolation.
- SHOULD prefer a model that reduces duplicate interactions and matches user intuition during composition.
- MUST NOT introduce a smarter-looking model that becomes harder to reason about in playback or export.

## Plan

First map the current contract of `targetDuration` in plain language: what it controls in generation, how it affects layer editing, and where playback and export rely on it as duration authority. Then compare a small number of candidate models against that contract rather than arguing only from the current UI.

The main candidates worth comparing are:
- explicit global target duration remains the source of truth
- effective length is derived from the longest active layer
- the current single value is split into separate concepts, likely something like preferred generation length versus effective playback length

Whichever direction looks strongest should then be tested against a few concrete scenarios: adding or trimming layers in a multi-layer hypnogram, extending a composition without wanting to re-trim every layer by hand, generating new clips from current settings, and exporting or replaying a clip whose visible content length and authored target length might differ. The spike should end with a recommendation for the next prototype or implementation slice, not just a restatement of the tension.
