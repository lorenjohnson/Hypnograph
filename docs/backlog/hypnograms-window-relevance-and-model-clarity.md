---
doc-status: draft
---

# Hypnograms Window: Relevance and Model Clarity

## Overview

The current Hypnograms window is a legacy surface from an earlier windowing approach in the app. It predates the SwiftUI sidebar pattern, and Hypnograph now appears to be moving again toward AppKit-managed floating windows. That makes this project less about polishing one existing window in place and more about deciding whether this surface still deserves to exist, and if so, in what form.

Right now the window feels visually old-style, can appear underneath or behind other UI, and has an unclear mental model. There is also product confusion in what it is meant to contain: app-managed recents, favorites, saved `.hypno` files, live clip history, or some mixture of those. On top of that, future sequence or sets work may reshape this area again, so it would be easy to over-invest in a surface that is about to be retired or replaced.

The clearest useful direction from earlier notes is this: if a `Hypnograms` surface survives, it should probably become one coherent browsing surface for `History`, `Saved`, and `Favorites` rather than a vague legacy window centered on `Recents`. `History` would mean live clip history, `Saved` would mean intentionally kept hypnograms, and `Favorites` would remain a subset of saved items. Those categories should feel related but not collapsed into one storage model. In particular, live history should not automatically become full saved-recipe persistence just to make the UI easier.

That said, this project should not assume the answer is "expand the legacy window." The real question is whether to improve and modernize this surface, reshape it into the newer window model, or retire it for now until Hypnograph has a clearer longer-term browsing model.

## Rules

- MUST decide whether this surface should be improved, reshaped, or temporarily retired.
- MUST treat the current window as legacy UI rather than assuming it is the final form to build on.
- SHOULD prefer one coherent `Hypnograms` browsing surface over separate overlapping `Recents` and `Favorites` concepts if the surface survives.
- MUST keep `History`, `Saved`, and `Favorites` conceptually distinct even if they appear together in one surface.
- MUST NOT convert live clip history into full saved-recipe persistence unless there is a stronger reason than UI consistency.
- SHOULD assume any surviving version of this surface needs to fit the newer AppKit window direction rather than the old embedded/sidebar-era assumptions.

## Plan

First decide the product stance: retire this surface, keep it with a narrower purpose, or reshape it into a clearer `Hypnograms` window that belongs in the newer window model. That decision should come before implementation detail, because otherwise we risk solving the wrong problem on top of legacy UI.

If the surface survives, the likely next shape is a unified browsing window with `History`, `Saved`, and `Favorites`, shared row treatment, and lightweight thumbnail support for history where useful. Keep that initial shape modest. The point is to make the model legible and the surface feel intentional, not to prematurely spec every row action, metadata field, or persistence detail before the larger relevance decision is settled.
