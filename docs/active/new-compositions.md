---
doc-status: draft
---

# New Compositions

## Overview

Hypnograph currently treats "new composition" and "generated composition" as almost the same thing in practice. The clearest current creation path is to play or step to the end of the sequence and let the app generate forward from the current generation parameters. That leaves a meaningful usability gap: there is no explicit way to insert a new composition after the current one and simply start from a blank slate.

This project is about separating those concepts. "New Composition" should become a first-class document action that inserts directly after the current composition, regardless of whether the current composition is at the end of the sequence. Generation should become a creation behavior that can be applied when appropriate, rather than being the only practical path to creating a composition.

The likely shape is that manual composition creation supports two modes:

- create a generated composition using the current generation parameters
- create a blank composition, initially behaving like an all-black gap with a sensible default duration

Playback-driven "generate at end" remains a different behavior. When that playback option is enabled and the sequence advances off the end, Hypnograph should continue generating new compositions rather than creating blanks.

## Rules

- MUST add an explicit composition-creation action that inserts after the current composition, not only at sequence end.
- MUST treat "new composition" and "generate composition" as related but distinct concepts.
- MUST preserve the existing playback-driven `generate at end` behavior as generation-only; it MUST NOT create blank compositions.
- SHOULD allow manual composition creation to use current generation parameters when generation-on-create is enabled.
- SHOULD support manual composition creation as a blank composition when generation-on-create is disabled.
- SHOULD choose a sensible default blank duration for the first useful version, likely around five seconds.
- MUST decide whether a blank composition is truly layerless or implemented as a black placeholder composition without leaking that implementation detail into the UI.
- MUST NOT require sequence playback in order to create a new composition.

## Plan

- Smallest meaningful next slice: define the operator-facing creation model and command surface for `New Composition`, including insertion point, blank-vs-generated behavior, and how this relates to the existing generation parameters.
- Immediate acceptance check: an operator can create a new composition directly after the current one without needing to advance to the end of the sequence, and the intended result is clearly either generated or blank based on the chosen creation behavior.
- Follow-on slice: implement blank composition support in the underlying model and renderer path, then wire explicit menu and UI actions for creation.

## Open Questions

- Should there eventually be one `New Composition` action whose behavior depends on a creation setting, or two explicit actions such as `New Composition` and `Generate Composition`?
- Should a blank composition be represented as zero layers, or as a black placeholder composition for now?
- What default blank duration feels right for the first useful version?
- Should insertion always be directly after the current composition, or do we eventually want insert-before / insert-at-end variants too?
