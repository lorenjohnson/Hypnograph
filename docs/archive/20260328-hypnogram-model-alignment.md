---
doc-status: done
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
| `ClipHistoryFile` / `ClipHistoryStore` | `HistoryFile` / `HistoryStore` | history of previously generated or visited Compositions in Studio | rename in this project as part of the same model cleanup |

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

### Adjacent Systems That Actually Align Cleanly

Some nearby naming that looked ambiguous turns out to map cleanly once the core rename is accepted.

- `ClipHistoryFile` is not really about top-level Hypnograms. It stores the history of the playable units inside Studio.
- under the target model, that means it is really `HistoryFile`
- `ClipHistoryStore` should likewise become `HistoryStore`
- `hypnograms` inside that history payload should become `compositions`
- `currentHypnogramIndex` inside that history payload should become `currentCompositionIndex`

So this history system does not create a contradiction in the rename. It is actually one of the clearer downstream confirmations that the target model is coherent.

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
5. In a second pass, decide which canonical encoded keys should change after the type rename has already landed cleanly.

## Completion Notes

This pass is complete enough to stop here.

- HypnoPackages has landed the core type rename:
  - `HypnographSession` -> `Hypnogram`
  - playable-unit `Hypnogram` -> `Composition`
  - `HypnogramLayer` -> `Layer`
- Hypnograph now builds successfully against those renamed package types.
- the app-side rename work now aligns the main conceptual surfaces and supporting terminology:
  - `ClipHistoryFile` / `ClipHistoryStore` -> `HistoryFile` / `HistoryStore`
  - `SessionStore` / `SessionFileActions` -> `HypnogramFileStore` / `HypnogramFileActions`
  - player-owned top-level model references from generic `session` language toward `hypnogram`
  - user-facing `Global` -> `Composition` and mistaken `Source` -> `Layer` cases
- the app-side persistence pass is now also in place:
  - `HistoryFile` now writes `compositions` and `currentCompositionIndex` while still decoding the older history keys
  - Studio settings now write composition-level keys and enum values while still decoding the older clip-named settings
  - the history file path now moves forward from `clip-history.json` to `history.json` with a legacy fallback read
- the package-side persistence pass is now also complete:
  - top-level Hypnogram JSON now encodes `compositions` as the canonical on-disk key
  - backward decode support is still preserved for legacy `hypnograms`, `clips`, and top-level `sources`

This means the model rename is no longer speculative. It now carries through both the shared package layer and the app, including persistence, while still opening older saved files.

### Immediate Acceptance Check

- we can point to each current core type and say what it will be called after the rename
- we can explain how older saved files will still open
- we have separated the true model rename from larger Sequences behavior questions

## Review Notes

- New files are intentionally one-way compatible: current Hypnograph can open older files, but older app versions will likely not open newly saved files.
- Backward decode compatibility remains in place for older saved hypnograms and older settings/history payloads.
- If a later iteration wants to rename the top-level saved file/container from `Hypnogram` to `Hypnograph`, that should now be a much smaller, more deliberate follow-up rather than part of this foundational cleanup.
