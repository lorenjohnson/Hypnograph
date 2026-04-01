---
doc-status: in-progress
---

# Effects and Effect Chain UX

## Overview

Hypnograph's current effects and effect-chain system is already powerful, but it still feels harder to understand and operate than it should. The rough edges cluster around the same area: what ships by default, how a user applies or replaces a chain, how chains are saved and restored, and what happens when a hypnogram opens with chains that are not in the current library.

This project now has three phases of attention:

1. curate the canonical shipped set of base effects and effect chains
2. refine the UX and mechanics around applying, replacing, saving, restoring, defaulting, and editing effect chains
3. review and simplify the story around opening hypnograms whose effect chains do not cleanly match the current library

The first phase is the current priority. It gets us closest to a releasable experience, because once the shipped set is strong enough, many users can simply apply chains until they find a look they like without needing to build or deeply manage chains themselves.

The second phase is the deeper dive for users who want to modify chains, author their own looks, or understand how library state behaves. One particularly important problem there is that the current `Add Effect` menu mixes individual effects and full effect chains in one surface, which makes it too easy to replace a whole chain when the user may think they are only appending an effect.

The third phase is about imported or unmatched chains from opened hypnograms. There has already been substantial thought in this area, and the current implementation may be close to sensible, but the behavior is not yet clear enough in either the UI or the documentation.

This project should stay focused on interaction and model clarity plus the shape of the shipped effect surfaces. Deep engine changes or new effect implementation work belong elsewhere.

## Rules

- MUST treat shipped base-effect and effect-chain curation as the first slice of this project.
- MUST clarify the distinction between bundled defaults and the local installed working library.
- MUST review the UX of applying, replacing, and editing effect chains in both global and layer contexts.
- MUST review how imported effect chains are handled when they are not already present in the library.
- SHOULD eventually support documentation for what each base effect does, when to use it, and what other effects it pairs well with.
- SHOULD consider whether preview thumbnails belong in the effect-chain browsing and apply flow, but only after the higher-priority mechanics are clearer.
- MUST aim for a more intuitive model without removing useful capability by default.

## Reference Docs

- [current effect-chain curation](./current-effects-chain-curation.md)
- [current effects curation](./current-effects-curation.md)

## Plan

The first slice is only phase one: get to a canonical shipped set of base effects and effect chains.

That means:

1. keep refining the current working inventories for:
   - packaged effect chains
   - packaged base effects
2. cut the library down toward the essential, canonical release set
3. note any chains or effects that should be tuned, renamed, merged, or removed
4. clarify the difference between:
   - bundled defaults
   - the installed working library in a local build
5. identify the minimum developer workflow needed to overwrite or refresh the bundled defaults while curating from Debug / Xcode

The second slice, after the canonical set feels stronger, is to refine the mechanics of applying and editing chains. That includes the confusing combined `Add Effect` menu, which currently mixes "append an effect" and "replace the current chain with a library chain" in one surface.

The third slice is to re-approach imported chains from opened hypnograms: how they are identified, whether they should remain recipe-local until explicitly saved, how `(imported)` should be shown, and how save-to-library should behave without silent overwrites.

## Open Questions

- Which base effects belong in the initial release?
- Which effect chains belong in the initial release?
- What is the simplest developer workflow for updating bundled defaults while curating the shipped set from Debug / Xcode?
- When phase two begins, should chain replacement and effect appending become separate controls immediately?
- When phase three begins, should imported chains remain entirely recipe-local unless explicitly saved?
