---
doc-status: in-progress
---

# Overview

Studio's player/render path is still harder to maintain than it should be, even after the playback-and-panels cleanup. The current code is not impossible to follow, but several boundaries still feel more accidental than intentional:

- `Studio.makeDisplayView()` mixes state ownership with view construction
- `player` and `playback` naming overlap in ways that make ownership and responsibility less clear
- the current `Studio/Playback/` subtree does not yet read as a fully coherent player area
- some state and behavior names carry historical wording that no longer matches the cleanest structural model

This project is about tightening that core Studio player organization so the main display path, the state path, and the naming path all reflect a better architectural model. The goal is not to make the code merely appear simpler. The goal is to make it more maintainable, more extensible, and more internally coherent, even if that means taking a broader look at the whole player path at once rather than optimizing for a tiny incremental slice.

The intended direction is:

- keep a dedicated player subtree
- use `Player` as the structural noun instead of `Playback`
- carry that naming consistently through state, coordinators, and views
- reduce `playback` as a noun to the minimum truly behavior-specific cases, if any remain
- clarify the ownership boundary between `Studio` and player-facing views so future changes have a more honest home

## Scope

- MUST improve the architecture of the Studio player path, not just its surface readability.
- MUST make the main Studio player/render path easier to maintain and extend.
- MUST keep a dedicated player subtree, but rename it from `Playback` to `Player`.
- MUST use `Player` consistently as the primary structural noun across the subsystem.
- MUST reduce or remove `playback` as a noun where it is currently standing in for the player itself.
- MUST revisit whether `Studio.makeDisplayView()` should remain on `Studio`, or move into a more honest view-level owner.
- MUST make the ownership boundary between `Studio`, player state, player coordinators, and player views more legible.
- MUST reduce incidental plumbing across the player path rather than increasing it.
- SHOULD prefer local names such as `loopMode` or `onStoppedAtEnd` when surrounding context already establishes the player scope.
- SHOULD preserve current runtime behavior while improving naming, ownership, and file organization.
- SHOULD prefer direct ownership and data flow over extra pass-through bindings, wrappers, or forwarding layers when those do not clearly simplify maintenance.
- MUST NOT introduce framework-like abstraction that does not immediately improve the player architecture.

## Plan

- Coordinated architecture pass:
  - map the current Studio -> player render path and state path
  - choose the target ownership model for player-facing view construction
  - rename the structural subtree and related types from `Playback` to `Player`
  - tighten behavior/state naming so the subsystem reads consistently as `Player`
  - reconcile the resulting file layout, coordinator names, and view names in one pass rather than as isolated micro-refactors
- Immediate acceptance check:
  - the main player path has one clear structural noun: `Player`
  - it is obvious where player state lives, where the player surface is built, and where runtime coordination belongs
  - `Studio` no longer carries player-view construction only because of historical convenience
  - the resulting structure feels more extensible for future player changes rather than merely shuffled
  - the resulting structure has less incidental plumbing and fewer pass-through layers than the current one

## Open Questions

- Should the main wrapper view be expressed directly in `ContentView`, or as a dedicated Studio player/container view?
- Which behavior names truly still need the word `playback`, if any, once the subsystem is consistently organized as `Player`?
- Does any coordinator or type still need both words once the surrounding path already establishes player context?
