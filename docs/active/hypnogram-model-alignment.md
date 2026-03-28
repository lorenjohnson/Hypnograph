---
doc-status: draft
---

# Hypnogram Model Alignment

## Overview

This project is about bringing the code and UI naming into closer alignment with the higher-level model we actually want for the app.

That model is now much clearer:
- a Hypnogram is the top-level saved unit
- a Hypnogram contains one or more Compositions in sequence
- a Composition contains one or more Layers

Right now the code does not line up cleanly with that language. In particular, the type currently named `HypnographSession` behaves most like a Hypnogram, while the type currently named `Hypnogram` behaves most like a Composition. This mismatch is already creating confusion in docs, UI naming, and design thinking around upcoming Sequences work.

The purpose of this project is not to change behavior first. It is to define a careful alignment path so the code, saved-model vocabulary, and user-facing language can move toward the same conceptual model without creating unnecessary churn or breaking existing persistence.

This may touch code in Hypnograph and may also touch some shared types in HypnoPackages if the cleanest alignment requires it.

## Rules

- MUST treat the glossary model as the intended top-level vocabulary unless revised explicitly.
- MUST distinguish naming alignment from behavior changes.
- SHOULD prefer the smallest rename slices that reduce confusion without destabilizing persistence.
- MUST identify which names are safe to change in code immediately and which names need compatibility handling or deliberate migration.
- MAY leave serialized keys or legacy compatibility names in place temporarily if that reduces risk.
- MUST consider both Hypnograph and HypnoPackages where shared model names are involved.
- MUST NOT let this become an unbounded abstraction cleanup unrelated to the core model terms.

## Plan

First map the current code abstractions directly onto the glossary terms so the rename surface is explicit: which types, files, comments, menu labels, and persistence names currently correspond to Hypnogram, Composition, and Layer. Then separate that map into low-risk naming changes, higher-risk persistence/schema changes, and questions that depend on Sequences.

Smallest meaningful next slice:
- produce a concrete rename/alignment map before changing any deeper model types

Immediate acceptance check:
- we can point to each current core type and say whether it should stay as-is, be renamed now, or be deferred for compatibility reasons

## Open Questions

- whether the current middle entity should be stabilized fully as `Composition` everywhere, or whether any user-facing `Clip` language still deserves to survive
- whether `HypnographSession` should eventually be renamed directly to `Hypnogram`, or whether a staged compatibility layer is safer
- whether any of this alignment should wait for Sequences, or whether doing it first is what will make Sequences finally easier to reason about
