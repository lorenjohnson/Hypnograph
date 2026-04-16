---
doc-status: draft
---

# Overview

Studio's player/render path is still harder to reason about than it should be, even after the playback-and-panels cleanup. The current code is not impossible to follow, but several boundaries still feel more accidental than helpful:

- `Studio.makeDisplayView()` mixes state ownership with view construction
- `player` and `playback` naming overlap in ways that make the main path harder to hold in one’s head
- the current `Studio/Playback/` subtree may now be more indirection than clarity
- some state and behavior names carry extra context (`playbackLoopMode`, `onPlaybackStoppedAtEnd`) where simpler local names may read more honestly inside the player path

This project is about tightening that core Studio player organization so the main display path, the state path, and the naming path all feel more direct. The intended outcome is not a broad architecture rewrite. It is a smaller, clearer structure where the primary player surface is easier to locate, the ownership boundary between `Studio` and views is more legible, and naming reflects the real mental model instead of historical layering.

## Scope

- MUST make the main Studio player/render path easier to locate and understand.
- MUST revisit whether `Studio.makeDisplayView()` should remain on `Studio`, or move into a more honest view-level owner.
- MUST reduce unnecessary overlap between `player` and `playback` naming where both currently describe the same area.
- MUST reassess whether `Studio/Playback/` still earns its own subtree, or whether flattening back into `Studio` would now be clearer.
- SHOULD prefer local names such as `loopMode` or `onStoppedAtEnd` when surrounding context already makes the player scope obvious.
- SHOULD keep `Studio` focused on state, actions, and coordination rather than view construction where possible.
- SHOULD preserve the current runtime behavior while improving naming and file organization.
- MUST NOT introduce new framework-like abstraction that does not immediately simplify the player path.

## Plan

- Smallest meaningful next slice: map the current Studio -> player render path and choose the target ownership/naming model before moving files or symbols.
- Immediate acceptance check: the target structure answers, in one quick scan, where the player surface is built, where player state lives, and whether `player` or `playback` is the primary organizing noun.
- Follow-on slices:
  - flatten or retain the `Playback` subtree based on that decision
  - move display-path view construction to the most honest owner
  - tighten naming around loop/stop/player runtime behavior

## Open Questions

- Should the main wrapper view be expressed directly in `ContentView`, or as a dedicated Studio player/container view?
- Should `player` become the primary noun everywhere structural, with `playback` reserved only for behavior verbs?
- Does `PlayerPlaybackCoordinator` still need both words in its name if the surrounding path already establishes player context?
