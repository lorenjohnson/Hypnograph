---
doc-status: draft
---

# Effects and Effect Chain UX

## Overview

Hypnograph's current effects and effect-chain UI is functional and fairly capable, but it still feels harder to understand and operate than it should. The rough edges seem to cluster around the same area: choosing and applying effect chains, understanding what happens when a chain is selected or replaced, managing chains from the library surface, and keeping the experience coherent between global and per-layer contexts.

This project is a spike because the need is clear, but the right simplification probably wants a more deliberate pass before implementation. The goal is to make the effects workflow much more intuitive without throwing away the current power. That includes the current effect-chain library window, the "current chain" experience, the semantics of applying versus replacing versus editing a chain, and smaller UX questions like whether effect-chain options should be enableable and disableable more directly from the sidebar.

It also includes the question of whether effect chains should have preview thumbnails as part of the browsing and apply flow. That could mean thumbnail-first library rows, applying a chain by pressing its preview, and optionally letting the user capture the current hypnogram as the thumbnail image for a chain. Those ideas belong here because they affect how the library feels to use, not just how it looks.

This should stay focused on interaction and model clarity, not on curating which chains or effects are worth shipping. Packaged library curation belongs in a separate backlog project.

## Rules

- MUST review the UX of applying, replacing, and editing effect chains in both global and layer contexts.
- MUST review the effect-chain library window and surrounding management flow for clarity and discoverability.
- SHOULD include smaller adjacent controls that affect the same UX surface, such as direct enable or disable treatment for effect-chain options in the sidebar.
- SHOULD consider whether preview thumbnails should become part of the effect-chain browsing and apply model.
- MUST aim for a more intuitive model without removing useful capability by default.
- MUST keep this project focused on UX and model clarity rather than on curating the packaged chain set itself.

## Plan

Start by writing down the current effects-chain interaction model in plain language: what happens when a chain is selected, what happens to the current chain, what happens differently in global versus layer contexts, and what the library window is actually for. Then identify the places where that model feels surprising, overloaded, or too indirect.

From there, shape a simpler UX direction for the whole area rather than patching individual annoyances one by one. That should include deciding whether preview thumbnails are worth using as part of chain browsing, applying, and authoring, and whether there should be a lightweight way to capture the current hypnogram as a chain thumbnail. The spike should end with a clearer interaction model and a small set of follow-on implementation slices, likely covering chain application semantics, library-window simplification, direct sidebar controls, and any thumbnail-based browsing behavior that proves worthwhile.
