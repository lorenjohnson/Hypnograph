# Hypnograph North Star: Persistent Clip Tape + Layered Clips

**Created**: 2026-01-15  
**Status**: Proposal / Planning

The app is one machine:

You watch and author a persistent **clip tape** (an ordered history of clips). Each **clip** is a layered montage (1…N layers). Preview plays clips in order. Render exports clips in order. No separate “montage mode” or “sequence mode”.

If `layers = 1`, the machine becomes “single clips in sequence”.

## The model

Clip = one authored unit: duration + play rate + layers + effects.  
Layer = one simultaneously-playing source within a clip (media slice + blend + effects).  
Clip tape (history) = the ordered list of clips you can go back to, edit, delete, and render.

The sequence you care about is a sequence of **clips**, not a sequence of **sources**.

## The knobs (UI-level decisions)

Clip count: `N` or `∞`  
History size: keep last `K` clips (default 100–200), persisted  
Clip length: min/max range (default 2s–15s; randomized per new clip)  
Layers: max layers (and optionally randomize layer count per new clip)  
Blend modes for new clips: Default (Screen) vs Randomize  
Global effects for new clips: Randomize Global Effect (toggle; OFF = carry forward previous clip’s global chain; ON = random from all templates)  

Per-clip play rate is part of the clip, not global.

Aspect ratio, resolution, and audio are global output settings (apply to preview/live/render).

Clip transitions are hard cuts for now (future transition styles are out of scope).

## Playback and history behavior

There is no separate Watch toggle. “Endless watching” is `clipCount = ∞`.

The tape is always retained (up to `K`):

- If you jump back, play continues forward through already-generated future clips.
- If playback reaches the end of the tape, the app generates a new clip and appends it.
- If the tape is at capacity, the oldest clips drop off the front.
- Editing overwrites that clip in place; it does not prune future clips.
- Deleting a clip removes it from the tape; past and future clips remain.
- Provide a menu item: “Clear Clip History” (resets tape to empty and generates a fresh clip).

Finite `clipCount = N` behaves like a predictable run:
- The system ensures there are `N` clips materialized for the run.
- Playback loops within those `N` (same clips, same choices).
- If clips are deleted and the run drops below `N`, new clips are generated to fill back to `N`.

## Render behavior (preview == render)

Render exports the exact materialized clips from the tape (same layers, blends, effects, play rates), concatenated in order.

Keep render UI minimal at first:
- For `clipCount = N`: render the current `N`-clip run.
- For `clipCount = ∞`: render the last `N` clips (prompt for `N`).

## Why this collapses the codebase

One state model (clip tape + clips) replaces two modes and two decks. Preview and render share the same materialized data. The branching caused by “montage vs sequence” largely disappears.

## UI surfaces (how it shows up)

Clip Set / Transport (sequencing + generation defaults)
- clipCount (N/∞), history size, navigation, delete clip, clear history, render
- defaults for new clips: clip length policy, layers policy, blend policy, randomize global effect toggle

Clip Editor (authoring the current clip)
- per-clip duration and play rate
- add/remove layers, swap sources, transforms, blend modes, per-layer effects, per-clip global effect

Output (global)
- aspect ratio, resolution, audio device + volume

Effects (separate window, as today)
- edits whichever target is selected for the current clip (global or a specific layer)

## Keep in mind (renderer direction, not a commitment yet)

Long-term, the render pipeline likely wants to be “render a clip tape”:

Layered composition inside each clip, and sequential concatenation across clips, handled by one export path.

That suggests eventually collapsing “montage timeline” vs “sequence timeline”, but we don’t need to decide internal renderer architecture to adopt this top-level model.

---

## Addendum: Current parameters that affect preview vs render (inventory)

This is a reference list to help map today’s implementation onto the model above. It’s intentionally flat.

### Preview-affecting parameters (today)

Global
- `Settings.watch` (enables watch timer)
- `Settings.watchInterval` (derived from montage recipe duration)

Per-player / generation
- `PlayerConfiguration.maxLayers` (max simultaneous layers when generating new clips)
- `Settings.clipLengthMinSeconds`, `Settings.clipLengthMaxSeconds` (target duration range for newly generated clips)
- `HypnogramRecipe.targetDuration` (realized per-clip duration; influences random clip slice length)
- `HypnogramRecipe.playRate`

Per-source / content
- `HypnogramRecipe.sources[]` (files, clip start/duration, transforms, blend modes, per-source effect chains)
- `HypnogramRecipe.effectChain` (global effects)

Display / routing
- `PlayerConfiguration.aspectRatio`
- `PlayerConfiguration.playerResolution`
- `Dream.liveMode` (preview vs live target)
- Preview audio device + volume
- Pause/navigation: `currentSourceIndex`, `currentClipTimeOffset`, `isPaused`
- Temporary preview overrides: global effect suspend, flash solo

### Render-affecting parameters (today)

Export setup
- Output folder (`Settings.outputURL`)
- Output size (derived from aspect ratio + resolution)
- Frame rate (currently 30)

Export content / duration
- Render uses a copied recipe (so all sources/transforms/effects apply)
- Duration uses `HypnogramRecipe.targetDuration`
