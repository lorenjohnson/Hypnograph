---
doc-status: draft
---

# Hypnograms Window: Relevance and Model Clarity

## Overview

The current Hypnograms window basically works, but its purpose and tab model need a focused product review. The question is no longer whether this surface is an artifact of an older UI direction. The useful question is whether the current functionality is clear enough, whether the existing `Recents` and `Favorites` tabs are the right model, and whether the window should include additional tabs such as `History` or `Saved`.

The main ambiguity is what each collection is meant to represent. `Favorites` is relatively clear. `Recents` is less clear, especially in relation to recently saved hypnograms versus live browsing history. This project should clarify what the current tabs actually query, whether those meanings are legible to the user, and whether the surface needs a more explicit tab set to match the real data model.

This is a narrower backlog project than a broad redesign. The goal is to review the current behavior, tighten the model, and decide whether the window is already sufficient with clearer semantics or whether it should grow into a more explicit browsing surface.

## Rules

- MUST review the current Hypnograms window behavior before proposing redesign.
- MUST clarify what `Recents` and `Favorites` actually mean in the product model.
- SHOULD decide whether additional tabs such as `History` or `Saved` are needed.
- MUST keep `History`, `Saved`, and `Favorites` conceptually distinct if they appear together in one surface.
- MUST NOT collapse live history into saved persistence just to simplify the UI model.

## Plan

First review the current tabs and their real data sources so the product model is explicit rather than inferred. Then decide whether the current two-tab shape is already sufficient, whether the naming needs refinement, or whether the window should add clearer tabs such as `History` or `Saved`.

If the surface expands, keep the change modest and driven by model clarity. The goal is to make it obvious what the user is browsing, not to turn this into a large browsing-system redesign.
