---
doc-status: draft
---

# Effects Engine Pass Graph Pivot Spike

## Overview

This spike is about one long-term question: should Hypnograph pivot from the current linear effects-chain runtime to a pass-graph effects engine as the main model going forward?

The pressure behind that question is not only technical. Hypnograph's current effects are often strong, but they can still land more "digital" than the analog signal character the product keeps reaching for. A lot of the most convincing references in this area are built as explicit multi-pass pipelines, and the gap between those references and Hypnograph's current linear model is becoming a recurring product constraint rather than an occasional annoyance.

So this spike should decide whether pass-graph is the real destination or just an interesting side path. If the answer is yes, it should also clarify what that means for the current runtime, for Effects Composer, and for how much compatibility work matters. The current working bias is that a pass-graph-first engine is probably the right long-term direction, and that OFX is at most an adapter or interoperability consideration rather than the core model. But that bias should be tested, not assumed.

This is not an implementation project. It is a decision-and-direction spike. The value of the document is to leave behind a clear architecture stance, a short list of minimum graph capabilities, and a follow-on implementation brief that could actually be picked up later without reopening the whole question. It should also make clear whether the current effects runtime is something to keep extending for a while or more of a stepping stone to replace once the new path is viable.

Useful reference context includes the current effects architecture in [effects.md](../reference/effects.md), the earlier effects-system refactor notes in [20260111-effects-system-refactor.md](../archive/20260111-effects-system-refactor.md), and external reference work such as RetroArch `slang-shaders`, `RetroTVFX`, and related analog-style shader pipelines that are hard to express cleanly in a strictly linear chain.

## Rules

- MUST decide whether pass-graph is the default long-term runtime direction or not.
- MUST identify the minimum graph capabilities needed to achieve the target visual character credibly.
- MUST clarify the transition posture from the current runtime if the pivot is approved.
- MUST say what this means for Effects Composer in the transition period.
- MAY discuss OFX and interoperability, but MUST NOT let that replace the core runtime decision.
- MUST NOT turn this spike into a full migration or implementation plan.
- SHOULD avoid committing to a long-lived dual-runtime future unless there is a strong reason.

## Plan

Define the smallest useful pass-graph contract in plain language, ideally against a few representative analog-style pipelines that are awkward or compromised in the current linear model. Then compare that model against the current runtime in terms of output quality, performance expectations, and authoring friction.

If pass-graph still looks right after that comparison, the spike should end with a concise go/no-go decision, a transition stance for the current runtime, a short note on how Effects Composer fits into that transition, and an active-ready implementation brief. If it does not look right, the spike should say why and make the case for continuing with the current linear system more intentionally rather than leaving the question half-open.
