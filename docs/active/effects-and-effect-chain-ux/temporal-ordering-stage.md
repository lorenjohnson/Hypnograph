---
doc-status: draft
---

# Temporal Ordering Stage

## Overview

Hypnograph's current effects system is increasingly strong at transforming images, but it is still weak at shaping what happens through time. As sequences become more central, the product gap is becoming clearer: a strictly linear sequence gets visually interesting frame-to-frame, but can still feel temporally boring.

The missing capability is not only "more effects." It is a new stage that can operate on ordering, recurrence, interruption, pacing, and return. In other words: a temporal ordering stage on top of the current resource-transform stages.

This stage should be thought of as separate from the current effects chains, even if it eventually lives nearby in the product model. The current effects stack is best understood as resource transformation:

- per-layer effects transform individual resources
- composition effects transform the composed result

What is missing is a stage that can influence:

- what returns
- what is interrupted
- what repeats
- what alternates
- what gets withheld and reintroduced
- what ordering or overlap happens through time

This matters now because the current sequence work is making the limitation more visible. The app is beginning to want a stronger temporal language than "one composition after another." It also suggests a deeper runtime idea: a composition is a pool of concurrently available visual resources, while a sequence is a pool of compositions arranged through time. Those are different authoring levels, but they may eventually want related runtime operators.

This project is a spike, not an implementation commitment. The near-term goal is to define the smallest useful shape of a temporal ordering stage, validate that it fits the mission of Hypnograph, and identify one first slice that could be tried without forcing a premature engine rewrite.

## Rules

- MUST treat temporal ordering as distinct from ordinary image/resource transformation.
- MUST stay focused on runtime and product shape, not on building a full nonlinear editor.
- MUST clarify how this stage relates to both composition-level and sequence-level behavior.
- SHOULD preserve the possibility that sequence-level temporal operators and composition-level temporal operators are related instances of the same deeper runtime idea.
- SHOULD identify the smallest useful first slice that creates visible temporal behavior, not only architectural cleanup.
- MUST NOT assume that the existing linear effect-chain model is the final long-term runtime model.
- MUST NOT commit to a full graph-engine migration inside this spike.

## Plan

Smallest meaningful next slice:
- define the minimum contract for a temporal ordering stage in plain language
- describe how it differs from the current effects/resource-transform stages
- choose one concrete proof-of-concept behavior that would feel visibly new and aligned with the product

Immediate acceptance check:
- we can explain, in one short architecture sketch, where a temporal ordering stage would sit relative to layer effects, composition effects, and sequence playback
- we can name one first experiment that is more about temporal structure than image treatment
- we can say whether that first experiment belongs first at composition level, sequence level, or both

Optional checkpoints:
1. clarify whether composition-level multi-resource effects and sequence-level temporal ordering are two separate systems or two layers of one broader timed-resource model
2. define whether the first temporal operator should be generative, rule-based, or partly hand-authored
3. note what current engine seams are most relevant if this moves toward implementation

## Open Questions

- What is the smallest temporal operator that would feel meaningfully different from today's sequence playback?
- Should the first proof-of-concept happen at composition level, sequence level, or in a way that clearly anticipates both?
- Is the right long-term model "resource transforms plus timeline ordering," or something even more unified around timed resources?
- How much of the desired behavior should be explicit authoring versus parameterized random generation?
