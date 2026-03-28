---
doc-status: draft
---

# Play Rate vs History Playback Speed: Overlap and Precedence

## Overview

This is a semantics spike about two controls that appear to overlap: ordinary play-rate controls and the separate history playback speed control. Right now the scope and precedence between them is not obvious enough.

The main uncertainty is whether `history playback speed` overrides play rate more broadly than intended, and what happens when playback moves from older history back into newly generated clips. Even if the implementation is internally consistent, the current UX does not make the control boundary clear.

The simplest likely direction is to remove `history playback speed` for now and rely on existing play-rate controls. If it stays, its scope and precedence need to be explicit in both behavior and UI.

## Rules

- MUST remove ambiguity between play-rate controls and history playback speed.
- MUST clarify whether history playback speed is a separate concept or just duplicate control surface.
- SHOULD prefer the simpler model if the separate history-speed control is not earning its complexity.
- MUST make scope and precedence obvious if both controls remain.

## Plan

First describe the current contract in plain language: what `playRate` affects, what `history playback speed` affects, and what should happen when playback transitions between older history and newly generated clips. Then decide whether the cleaner answer is to collapse the model to one control or keep both with explicit, narrow responsibilities.
