---
doc-status: draft
---

# Overview

Playback and panel infrastructure in Studio are both becoming harder to reason about because their runtime logic is spread across role-based directories and view files. The code still works, but understanding either subsystem now often requires hopping across multiple files and reconstructing behavior mentally.

This project is to reorganize both playback and panels into clearer feature-scoped areas, and to centralize their runtime orchestration into coordinator-shaped objects where appropriate. The goal is not abstraction for its own sake. The goal is to make the code easier to read, safer to change, and less likely to accumulate fragile edge-case logic in view files.

The current intended direction is:
- use `Coordinator` as the naming convention for top-level runtime orchestration objects in this app
- introduce scoped directories for playback and panels
- include their related views inside those scoped areas if that proves coherent in practice, rather than keeping all views in one global `Views/` bucket by default

## Scope

- MUST evaluate Studio playback as one subsystem rather than continuing to let runtime playback logic accrete primarily inside `PlayerView`.
- MUST evaluate Studio panels as one subsystem rather than continuing to split panel runtime logic across unrelated top-level files.
- MUST prefer `Coordinator` naming for this class of runtime orchestration object and apply that choice consistently once this project begins.
- MUST test whether feature-scoped directories actually improve clarity, rather than assuming they do.
- SHOULD treat directory organization and interface cleanup as related work, not totally separate concerns.
- SHOULD reduce unnecessary use of the word `preview` in playback-related names when `playback` or `rendering` describes the role more directly.
- MAY move related views into `Playback/Views/` and `Panels/Views/` if doing so makes the subsystem boundaries easier to understand.
- MUST NOT force artificial boundaries if the resulting directories would lie badly about actual dependencies.

## Plan

- Smallest meaningful next slice:
  - map the current playback files and panel files that together form each subsystem
  - choose the initial destination structure for both subsystems
  - extract or rename only the first runtime owner needed to validate the pattern

- Immediate acceptance check:
  - a future reader should be able to locate playback orchestration and panel orchestration without searching across unrelated files
  - the naming should clearly distinguish runtime coordinators from models, services, and views
  - the resulting directory structure should make the real subsystem boundaries easier to understand, not harder

- Likely checkpoints:
  - playback organization first, since current playback behavior and still-image handling are exposing the orchestration problem more directly
  - panel infrastructure second, including a decision about whether panel views should move into the scoped area or remain under a shared views location

## Open Questions

- Does playback want one top-level coordinator, or a small set of tightly related coordinators with one clear owner?
- Should panel views move with panel infrastructure immediately, or should panel infrastructure move first and views follow later if that proves helpful?
- Are there any existing files that look like services but are really runtime coordinators already and should be renamed when this project begins?
