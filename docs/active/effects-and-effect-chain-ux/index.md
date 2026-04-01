---
doc-status: in-progress
---

# Effects and Effect Chain UX

## Overview

Hypnograph's current effects and effect-chain UI is functional and fairly capable, but it still feels harder to understand and operate than it should. The rough edges cluster around the same area: choosing and applying effect chains, understanding what happens when a chain is selected or replaced, managing chains from the library surface, and keeping the experience coherent between global and per-layer contexts.

This project remains a spike because the need is clear, but the right simplification still wants a more deliberate pass before implementation. The goal is to make the effects workflow much more intuitive without throwing away the current power. That includes the current effect-chain library window, the "current chain" experience, the semantics of applying versus replacing versus editing a chain, and smaller UX questions like whether effect-chain options should be enableable and disableable more directly from the sidebar.

It also includes the question of whether effect chains should have preview thumbnails as part of the browsing and apply flow. That could mean thumbnail-first library rows, applying a chain by pressing its preview, and optionally letting the user capture the current hypnogram as the thumbnail image for a chain.

This project now also covers:

- curating the shipped default effect-chain library
- curating the shipped base-effect list
- documenting what the base effects do and how they are best used
- clarifying how imported effect chains behave when opening old hypnograms or hypnograms created elsewhere
- clarifying the distinction between bundled defaults and the local installed working library

This should stay focused on interaction and model clarity plus the shape of the shipped library surfaces. Deep engine changes or new effect implementation work belong elsewhere.

## Rules

- MUST review the UX of applying, replacing, and editing effect chains in both global and layer contexts.
- MUST review the effect-chain library window and surrounding management flow for clarity and discoverability.
- MUST review how imported effect chains are handled when they are not already present in the library.
- MUST clarify the distinction between bundled defaults and the local installed working library.
- SHOULD include smaller adjacent controls that affect the same UX surface, such as direct enable or disable treatment for effect-chain options in the sidebar.
- SHOULD consider whether preview thumbnails should become part of the effect-chain browsing and apply model.
- SHOULD shape the shipped default library of both effect chains and base effects into something more deliberate and understandable.
- SHOULD eventually support documentation for what each base effect does, when to use it, and what other effects it pairs well with.
- MUST aim for a more intuitive model without removing useful capability by default.

## Current Behavior Notes

### Bundled Defaults vs Installed Library

There is an important distinction between the bundled default effect-chain set and the effect-chain library that exists in a given local installation.

- `Restore Default Effects Library` currently replaces the working library with the bundled defaults.
- `Save to Default Effects Library` currently saves to the user's installed library file, not back into the bundled defaults in the app bundle.
- There is already UI for:
  - restoring bundled defaults
  - saving the current working library to the installed default library file
  - saving the current library to an external JSON file
  - loading and merging / replacing from a JSON file or a hypnogram file

This means there is currently a way to overwrite the installed default library from the UI, but there is not yet a developer-facing way to overwrite the bundled defaults used for shipping.

That dev-only overwrite flow likely wants to exist eventually, especially while curating the shipped default library from Xcode / Debug runs.

### Imported Chains from Opened Hypnograms

When effect chains are extracted from a loaded hypnogram, current behavior is still fairly library-oriented:

- effect chains are extracted from global and per-layer contexts
- unnamed imported chains are given generated names ending in `(imported)`
- extracted chains are currently merged into the library session
- merge behavior in `EffectsSession` currently overwrites by chain name, not by `id`

At the same time, the underlying model does carry more identity information:

- each `EffectChain` has its own `id`
- recipe-owned copies can also carry `sourceTemplateId`
- applying a template to a recipe creates a new recipe-owned chain with a fresh `id`, linked back to the template through `sourceTemplateId`

So there is a mismatch worth revisiting: the runtime / recipe model is identity-aware, but the current library merge behavior is still name-based.

### Base Effects vs Effect Chains

The default install surface really has two curatorial layers:

- the base effects available in `Add Effect`
- the packaged effect chains available in the library

Both need refinement before release. The base effects need to feel versatile and worth learning; the effect chains need to feel like a strong authored default set.

## Desired Direction Notes

### Imported Chains Should Not Necessarily Enter the Library Immediately

An upcoming simplification worth exploring is:

- when opening a hypnogram that contains chains not present in the current library, do not silently merge them into the library
- instead, show them where they are already being used, with an `(imported)` label or equivalent treatment
- allow the user to explicitly save that chain into the library from the composition / layer context

That would make imported chains feel like session content first, and library content only when intentionally promoted.

### Save-to-Library Should Be Explicit and Safe

If an imported chain is explicitly saved to the library:

- it should become a new library entry
- it should not silently overwrite an existing chain just because the name matches
- the exact duplicate / update / fork behavior should be made explicit

This likely wants a clearer policy around:

- name collisions
- identity collisions
- when a chain counts as "the same template"
- what role `sourceTemplateId` should play in deciding update vs save-as-new

### Shipped Defaults Should Become More Deliberate

The shipped defaults should feel intentionally selected rather than like a dump of whatever currently exists.

That applies to both:

- the effect-chain library
- the base-effect list in the effect composer / add-effect menu

Eventually, the base effects also want accompanying documentation:

- what the effect does
- what kind of visual direction it serves
- what other effects it combines well with
- when it tends to be too aggressive or too subtle

## Reference Docs

- [current effect-chain curation](./current-effects-chain-curation.md)
- [current effects curation](./current-effects-curation.md)

## Plan

Start by writing down the current effects interaction model in plain language: what happens when a chain is selected, what happens to the current chain, what happens differently in global versus layer contexts, and what the library window is actually for. Then identify the places where that model feels surprising, overloaded, or too indirect.

From there, shape a simpler UX direction for the whole area rather than patching individual annoyances one by one. That should include deciding whether preview thumbnails are worth using as part of chain browsing, applying, and authoring, whether there should be a lightweight way to capture the current hypnogram as a chain thumbnail, and how imported chains should behave before they are intentionally saved to the library.

In parallel, keep refining the current working inventories for:

- packaged effect chains
- packaged base effects

The spike should end with a clearer interaction model and a small set of follow-on implementation slices, likely covering chain application semantics, library-window simplification, imported-chain handling, library curation flows, and documentation work for the base effect set.

## Open Questions

- Should imported chains remain entirely recipe-local unless explicitly saved?
- Should `(imported)` be a visual label only, part of the actual name, or both?
- Should save-to-library from an imported chain always create a new template first?
- Should the library merge behavior move away from name-based replacement toward `id` / `sourceTemplateId` semantics?
- What is the right developer-only workflow for updating bundled defaults while curating the shipped set from Debug / Xcode?
- Which base effects should ship in the initial release?
- Which effect chains should ship in the initial release?
