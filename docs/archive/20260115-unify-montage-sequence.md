---
doc-status: done
---

# Unify Montage/Sequence

This project unified the user model and code paths by:
- Removing "Sequence mode" as a concept and implementation path.
- Making Preview always a layered clip (1…N layers).
- Adding persistent **clip history** (ordered clips + current index) with navigation and deletion.

## The model

Clip = one authored unit: duration + play rate + layers + effects.
Layer = one simultaneously-playing source within a clip (media slice + blend + effects).
Clip history = the ordered list of clips you can go back to, edit, delete, and render (rendering a range is handled in a separate project).

The sequence you care about is a sequence of **clips**, not a sequence of **sources**.

## Playback and history behavior

The history is always retained (up to `historyLimit`):

- If you jump back, play continues forward through already-generated future clips.
- If playback reaches the end of the tape, the app generates a new clip and appends it.
- If the tape is at capacity, the oldest clips drop off the front.
- Editing overwrites that clip in place; it does not prune future clips.
- Deleting a clip removes it from the tape; past and future clips remain.
- Provide a menu item: "Clear Clip History" (keeps the current clip only).

## Why this collapses the codebase

One state model (clip tape + clips) replaces two modes and two decks. Preview and render share the same materialized data. The branching caused by "montage vs sequence" largely disappears.

## UI surfaces (how it shows up)

Clip Set / Transport (sequencing + generation defaults)
- clipCount (N/∞), history size, navigation, delete clip, clear history, render
- defaults for new clips: clip length policy, layers policy, blend policy, randomize composition effect chain toggle

Clip Editor (authoring the current clip)
- per-clip duration and play rate
- add/remove layers, swap sources, transforms, blend modes, per-layer effects, per-clip composition effect chain

Output (global)
- aspect ratio, resolution, audio device + volume

Effects (separate window, as today)
- edits whichever target is selected for the current clip (global or a specific layer)

## Out of scope (moved to its own project)

Saving/rendering a *range* of clips (sequence saving) is tracked separately in:
`docs/hypnograph/active/export-clip-history-fcpxml.md`

---

## Addendum: Current parameters that affect preview vs render (inventory)

This is a reference list to help map today's implementation onto the model above. It's intentionally flat.

### Preview-affecting parameters (today)

Global
- `Settings.watchMode` (advance/generate on clip end)

Per-player / generation
- `PlayerConfiguration.maxLayers` (max simultaneous layers when generating new clips)
- `Settings.clipLengthMinSeconds`, `Settings.clipLengthMaxSeconds` (target duration range for newly generated clips)
- `HypnogramClip.targetDuration` (per-clip duration; influences random clip slice length)
- `HypnogramClip.playRate`

Per-source / content
- `HypnogramClip.sources[]` (files, clip start/duration, transforms, blend modes, per-source effect chains)
- `HypnogramClip.effectChain` (composition effect chains)

Display / routing
- `PlayerConfiguration.aspectRatio`
- `PlayerConfiguration.playerResolution`
- `Dream.liveMode` (preview vs live target)
- Preview audio device + volume
- Pause/navigation: `currentSourceIndex`, `currentClipTimeOffset`, `isPaused`, `currentClipIndex`
- Temporary preview overrides: composition effect chain suspend, flash solo

### Render-affecting parameters (today)

Export setup
- Output folder (`Settings.outputURL`)
- Output size (derived from aspect ratio + resolution)
- Frame rate (currently 30)

Export content / duration
- Render uses a copied clip (so all sources/transforms/effects apply)
- Duration uses `HypnogramClip.targetDuration`
