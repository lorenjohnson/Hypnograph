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

This project now has a clearer intended direction. The remaining work is to carry that direction through the code carefully, without letting persistence compatibility or Sequences concerns create confusion.

### Current Mapping

| Current name | Intended name | Meaning in current model | Direction |
| --- | --- | --- | --- |
| `HypnographSession` | `Hypnogram` | top-level saved container/document | rename |
| `Hypnogram` | `Composition` | one playable unit inside the container | rename |
| `HypnogramLayer` | `Layer` | one layer inside a composition | likely rename directly to `Layer` |
| `effectChain` on current `Hypnogram` | composition-level effect chain | composition-wide effects | keep behavior, update surrounding naming |
| `HypnogramStore` / `HypnogramEntry` | likely keep | store of saved top-level files | already aligned closely enough with intended `Hypnogram` meaning |
| `ClipHistoryFile` / `ClipHistoryStore` | review later | history of compositions within the current hypnogram | defer until core rename lands |

### Rename Surface

The rename surface appears to break down into three categories:

1. Low-risk app and UI naming
- comments
- menu labels
- view model property names
- local variables like `currentHypnogram`
- file names that mirror the model terms

2. Core model and shared package naming
- `HypnographSession`
- `Hypnogram`
- `HypnogramLayer`
- any public helpers, initializers, or convenience APIs built around those names
- references in Hypnograph and in HypnoPackages

3. Persistence and compatibility
- serialized keys like `hypnograms`, legacy `clips`, legacy `sources`, and legacy `clip`
- any Quick Look or file-open paths that assume the old schema names
- save/load logic that must continue opening older saved files

### Intended Rules For This Rename

- `HypnographSession` should become `Hypnogram`.
- current `Hypnogram` should become `Composition`.
- `HypnogramLayer` should become `Layer` unless that proves concretely dangerous during implementation.
- user-facing and developer-facing naming should move toward the same model, not drift further apart.
- older saved files should continue to open.
- when an older file is opened and later re-saved, it should normalize forward into the newer naming/schema rather than preserving old terminology forever.
- legacy decode support is acceptable; long-term parallel naming throughout the code is not.

### Recommended Execution Order

1. Finish the mapping and freeze the intended names in this document and the glossary.
2. Rename the app-level and package-level model types.
3. Rename the obvious app state and UI references that currently mirror the old model names.
4. Preserve backward decode support for older saved files by continuing to accept legacy keys during decoding.
5. Decide separately whether the canonical encoded keys should change immediately in this same pass or in one short follow-up pass.

### Immediate Acceptance Check

- we can point to each current core type and say what it will be called after the rename
- we can explain how older saved files will still open
- we have separated the true model rename from larger Sequences behavior questions

## Open Questions

- whether canonical encoded keys should change in the same pass as the type rename, or whether we should first rename the types while continuing to encode the current schema keys
- whether `Layer` as a bare type name introduces any real ambiguity in shared code, or whether it is the cleanest choice
- how much related `Clip` terminology should be pulled along in adjacent systems like clip history during this pass versus left for a follow-up
