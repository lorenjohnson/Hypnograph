---
doc-status: in-progress
---

# Effects and Effect Chain UX

## Overview

Hypnograph's current effects and effect-chain system is already powerful, but it still feels harder to understand and operate than it should. The rough edges cluster around the same area: what ships by default, how a user applies or replaces a chain, how chains are saved and restored, and what happens when a hypnogram opens with chains that are not in the current library.

This project now has three phases of attention:

1. refine the core effects and effect-chain UX enough that curation can happen through the app with confidence
2. curate the canonical shipped set of base effects and effect chains using that improved workflow
3. review and simplify the story around opening hypnograms whose effect chains do not cleanly match the current library

The first phase is the current priority. The key realization is that curation is not actually separate from UX here. In order to responsibly cut down the shipped set and publish better defaults back into the app, the workflow for browsing, applying, editing, saving, and publishing effect chains needs to be clear enough that the curation work itself is not distorted by confusing tooling.

That first phase therefore includes a small amount of debug-oriented product work: enough app-facing functionality to make it obvious when a chain or effect is being saved to the local installed library versus being published back into the core bundled defaults. This is not the same as broad authoring tooling, but it is important because the curation loop itself depends on knowing what is local, what is bundled, and what should be promoted back into the core package.

The second phase is the actual curation pass once that workflow is good enough: cut the library down toward the canonical release set, tune or rename what remains, and use the app-facing publish-to-core workflow to iterate on the bundled defaults from real usage.

The third phase is about imported or unmatched chains from opened hypnograms. There has already been substantial thought in this area, and the current implementation may be close to sensible, but the behavior is not yet clear enough in either the UI or the documentation.

This project should stay focused on interaction and model clarity plus the shape of the shipped effect surfaces. Deep engine changes or new effect implementation work belong elsewhere.

This index is the umbrella project document for the whole effects and effect-chain UX area. The additional markdown files in this directory are active working notes within that umbrella, not separate queue entries. They exist to help sort and prioritize related strands of work without losing the fact that this is one substantial active area.

## Rules

- MUST treat core effects and effect-chain UX as the first slice of this project.
- MUST clarify the distinction between bundled defaults and the local installed working library.
- MUST review the UX of applying, replacing, and editing effect chains in both composition and layer contexts.
- MUST make the workflow for publishing curated effects and chains back into the core package clear enough to support real curation from the app.
- MUST review how imported effect chains are handled when they are not already present in the library.
- SHOULD eventually support documentation for what each base effect does, when to use it, and what other effects it pairs well with.
- SHOULD consider whether preview thumbnails belong in the effect-chain browsing and apply flow, but only after the higher-priority mechanics are clearer.
- MAY add small debug-oriented affordances that support curation and publishing without turning this into a large tooling project.
- MUST aim for a more intuitive model without removing useful capability by default.

## Reference Docs

- [current effect-chain curation](./current-effects-chain-curation.md)
- [current effects curation](./current-effects-curation.md)
- [effects-chain UX refinements](./effects-chain-ux-refinements.md)
- [effects engine pass-graph pivot spike](./effects-engine-pass-graph-pivot-spike.md)
- [temporal ordering stage](./temporal-ordering-stage.md)

## Plan

The first slice is now phase one: make the effects and effect-chain workflow coherent enough that curation can happen through the app without confusion.

That means:

1. refine the mechanics of applying and editing chains, especially where the current UI blurs:
   - appending an individual effect
   - replacing the current chain with a library chain
   - saving locally
   - publishing back to the bundled core set
2. clarify the difference between:
   - bundled defaults
   - the installed working library in a local build
3. identify the minimum app-facing debug workflow needed to:
   - copy an individual effect or effect chain back into the core package
   - copy the whole working set back into the core package
   - understand when a save is local-only versus core-publishing
4. keep using the current working inventories for:
   - packaged effect chains
   - packaged base effects
   as the material we refine through that improved workflow

The second slice, once that workflow is trustworthy, is to do the actual curation pass: cut the library down toward the essential canonical release set, note what should be tuned, renamed, merged, or removed, and use the publish-to-core workflow to keep the bundled defaults honest.

The third slice is to re-approach imported chains from opened hypnograms: how they are identified, whether they should remain recipe-local until explicitly saved, how `(imported)` should be shown, and how save-to-library should behave without silent overwrites.

The temporal-effects and pass-graph questions remain active, but they are downstream of the current curation and interaction work unless a concrete engine limitation blocks that path.

## Open Questions

- What is the smallest debug-facing publish-to-core workflow that makes curation practical without becoming its own tooling project?
- Should chain replacement and effect appending become separate controls immediately, or can a better single surface still be made safe enough?
- Which parts of the save/publish distinction should be surfaced directly in the app versus left as debug-only affordances?
- Once the workflow is clearer, which base effects belong in the initial release?
- Once the workflow is clearer, which effect chains belong in the initial release?
- When phase three begins, should imported chains remain entirely recipe-local unless explicitly saved?
