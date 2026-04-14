---
doc-status: draft
---

# Effects Chain UX Refinements

## Overview

This project groups a few related refinements around how effect chains are browsed, edited, previewed, and used for random generation. The common issue is that the current effect-chain library UI exposes more power than it can support clearly: parameters can be edited without live feedback, random selection treats the whole library too bluntly, and there is no lightweight way to preview a chain before applying it.

The three concrete areas currently in view are:

1. Effect-chain parameter editing is currently a foot gun. Inside the effect-chain library UI, parameters can still be edited even though their result is not visible live unless the chain is applied. That makes it too easy to accidentally persist changes to a chain without meaningful feedback. The likely short-term fix is to make those parameters read-only there, while a longer-term direction would be a preview/apply workflow.
2. Effect chains need a clearer random-selection model. The app likely needs a way to mark which chains are eligible for random use in new compositions, instead of treating the whole library as available. Longer term, that may expand into tags or categories, and then a selector in New Compositions that can target `All` or one or more tags like `dreamy` or `destructive`.
3. Previewing effect chains is a missing UX capability. It would be useful to preview an effect chain on the current composition or layer without immediately replacing the currently applied one. That could become a preview/apply flow, but for now it remains an exploration area rather than an immediate bug fix.

The short-term goal is not to redesign the whole effects system. It is to identify the smallest changes that make effect-chain behavior safer and more legible, while leaving room for a more expressive preview and categorization model later.

## Rules

- MUST treat accidental persistence of invisible effect-chain edits as a UX problem to resolve.
- MUST explore a clearer eligibility model for random effect-chain selection in new compositions.
- MUST consider preview behavior separately from permanent apply behavior.
- SHOULD prefer small safety and clarity improvements before building a larger effect-chain browsing workflow.
- MUST NOT assume tags, categories, or preview/apply flows are required in the first slice unless the simpler fixes prove insufficient.

## Plan

- Smallest meaningful next slice: decide whether effect-chain parameters in the library should become read-only until a clearer preview/apply model exists.
- Immediate acceptance check: there is a safer and more understandable model for browsing chains without silently mutating them.
- Follow-on slice: define how random selection eligibility should work, from a simple include/exclude flag up through tags or categories if needed.
- Later slice: explore a preview/apply workflow so chains can be auditioned without immediately replacing the currently applied one.

## Open Questions

- Should library-side effect-chain parameters be fully read-only for now, or is there a lighter safeguard that still prevents accidental persistence?
- Is a simple `eligible for random selection` toggle enough, or does the product really need tags or categories on chains?
- What is the smallest useful preview model: temporary apply, explicit preview button, or a more formal staged apply flow?
- How much of this belongs in the existing effect-chain library UI versus a later dedicated browsing or curation workflow?
