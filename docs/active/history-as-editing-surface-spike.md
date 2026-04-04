---
doc-status: draft
---

# History As Editing Surface Spike

## Overview

This spike is about exploring whether a couple of small interventions could make Hypnograph's existing history behave more like a rough editing surface before the fuller sequences/timeline work exists.

The main idea is to test whether history can already support a primitive "assemble a movie from generated compositions" workflow with minimal changes. The most concrete version of that is changing composition-level delete behavior so a composition can be removed from history instead of being immediately replaced, which would let history start acting more like a sequence the user can shape.

The second area is more tentative: exploring whether keyboard navigation should shift a little toward editing behavior, especially around left/right arrows while paused. That might mean clip-level frame stepping or clip-start nudging on one modifier path, while history navigation moves to another. This may turn out not to be worth doing, but it seems worth evaluating in the same spike because it asks the same broader question: how far can the current history/player model stretch toward editing before dedicated sequence tools exist?

The goal of this project is not necessarily to ship both ideas. The goal is to determine whether either of them is coherent, low-risk, and valuable enough to do now.

## Rules

- MUST treat this as an exploratory spike, not a commitment to ship both ideas.
- MUST keep the focus on small interventions that could improve pre-sequences editing behavior.
- MUST prefer deletion/removal behavior as the more concrete first question.
- SHOULD evaluate keyboard editing/navigation changes only if they stay small and legible.
- MUST NOT let this spike turn into full sequences or timeline implementation.

## Plan

- Smallest meaningful next slice: trace what would have to change for composition-level delete to remove a composition from history cleanly instead of immediately regenerating one.
- Immediate acceptance check: determine whether history deletion is simple and coherent enough to be worth doing as a standalone improvement.
- Follow-on slice: only if that looks promising, evaluate whether insert/replace behavior or keyboard editing/navigation changes belong in the same pre-sequences pass.

## Open Questions

- Is composition-level delete from history actually simple enough to ship without destabilizing the current history model?
- If deleting from history becomes possible, does that immediately imply that insert or replace behavior is also needed?
- Would arrow-key editing behavior make the app feel more like a useful rough-cut tool, or just create mode confusion before sequences exist?
- Is the right outcome here a tiny implementation pass, or a deliberate "wait for sequences" decision?
