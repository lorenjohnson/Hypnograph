---
doc-status: done
---

# Overview

Studio's player/render path was still harder to maintain than it should be, even after the playback-and-panels cleanup. The main problems were structural rather than cosmetic:

- `Studio.makeDisplayView()` mixed state ownership with view construction
- `player` and `playback` overlapped in ways that obscured ownership
- the `Studio/Playback/` subtree no longer matched the intended architectural boundary
- several settings and callback names still carried old noun choices that added noise rather than clarity

This pass tightened the core Studio player organization so the display path, state path, and naming path all reflect a cleaner architectural model. The goal was not to make the code merely look simpler. The goal was to make it more maintainable, more extensible, and more internally coherent.

## Outcome

- The dedicated player subtree now lives at `Hypnograph/App/Studio/Player/`.
- `Playback` was removed as the structural noun across the Studio player area in favor of `Player`.
- `ContentView` now owns the main player surface by rendering `PlayerView(main: main)`.
- `Studio.makeDisplayView()` is gone. `Studio` now exposes player-facing state and behavior helpers instead of manufacturing views.
- The render path is now:
  - `ContentView`
  - `PlayerView`
  - `PlayerRendererView`
  - `PlayerContentView`
- The old binding-heavy `PlayerView` representable was split into:
  - `PlayerView` as the SwiftUI owner of player/fallback display decisions
  - `PlayerRendererView` as the `NSViewRepresentable` bridge for the Metal/AppKit player surface
- Incidental plumbing was reduced by passing `Studio` through the player view boundary instead of forwarding a long list of bindings and callbacks.
- Player settings now encode new `loopMode` / `dockMode` keys while still decoding legacy `playbackLoopMode` / `playbackDockMode` keys for compatibility.
- The Studio model now safely returns a placeholder composition when the sequence is temporarily empty, avoiding the render-path crash risk that would otherwise have been introduced by removing the old synchronous view-factory mutation.

## Acceptance

- The main player path has one clear structural noun: `Player`.
- It is now obvious where player state lives, where the player surface is built, and where runtime coordination belongs.
- `Studio` no longer carries player-view construction for historical convenience.
- The resulting structure is more extensible for future player work because the view boundary, render boundary, and state boundary are more honest.
- The resulting structure has less incidental plumbing than the previous binding-heavy render path.

This project is complete enough to archive. Any future work here should be follow-on refinement, not completion of the structural rename and ownership pass itself.
