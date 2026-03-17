---
created: 2026-03-14
updated: 2026-03-17
---

## What Is Hypnograph

Hypnograph is a memory-forward visual instrument for macOS.

Instead of browsing your archive like a filing cabinet, Hypnograph replays your photos and videos as evolving, remixable sequences. It can begin in a generative mode where surprising combinations emerge quickly, and it can also be steered into deliberate composition through clip selection, timing, layering, blend modes, and effect chains.

The point is not to generate synthetic media. The point is to re-encounter material that already belongs to your life or project and shape it into something that feels newly alive, exploratory, and creatively useful.

What Hypnograph should become from here depends on real use. This document is part of that process.

## Download Hypnograph Beta

- Download latest build: [Hypnograph Beta (macOS)](https://github.com/lorenjohnson/Hypnograph/releases)
- Install: open the DMG, drag `Hypnograph.app` to `Applications`, then first launch via right-click `Open`
- If macOS shows a verification warning, this is expected for unsigned beta distribution
- If Apple Photos sources do not appear immediately after first permission approval, quit and relaunch once

Hypnograph is at a turning point where I need to sharpen what the app actually is by grounding it in real use, not only in internal iteration. The immediate need is to involve a small set of collaborators who can work with what already exists, use it seriously, and reflect back what feels meaningful, confusing, exciting, or missing in expected behavior.

In this stage, I'm most needing contribution in the form of folks trying it out and giving feedback to help focus and shape the tool. Careful rounds of use and feedback: what people try to do with the app, what they expect it to do, what it already does well, and where the tool can be narrowed or deepened.

The use cases below are the working foundation for that process, and will likely be shaped by your own feedback. For now they help identify who to invite, what sessions to run, and what product direction to prioritize while keeping authorship coherent and open to new ideas from people whose use feels relatable and concrete.

## Use Case 1: Personal Archive Exploration and Immersion

### Scenario

Use Hypnograph with your own photo and video history as a creative-reflective practice: move through personal archives, surface forgotten or overlooked material, and re-encounter your own past as something present and alive.

In this mode, playback can feel like watching your own life as a nonlinear "channel" in a default-mode-network kind of space: less task-driven searching, more open attention and pattern recognition.

### Why This Matters

- It turns static archives into living sequences with rhythm, contrast, and emotional texture.
- It supports rediscovery, not just retrieval: less catalog browsing, more felt meaning.
- It creates a path from reflection into authorship, where personal memory can be shaped into new visual forms.

### Media Management During Playback

- `Mark for deletion`: a single key can flag current media to a staged deletion flow (kept in the `Deleted` album under the `Hypnograph` folder in Apple Photos for later review).
- `Exclude`: permanently removes a clip from randomized playback without deleting it.
- `Favorite`: saves standout clips into the `Favorites` album under the `Hypnograph` folder in Apple Photos.
- This gives collaborators a practical way to curate while they watch, not only afterward.

## Use Case 2: Fresh-Off-the-Shoot Footage Exploration

### Scenario

After a shoot (for example, a short film with a large footage set), use Hypnograph early in the edit process to rapidly explore combinations of clips with smooth, cinematic-style transitions.

The randomized sequencing often places shots together that would not normally be considered in a first pass. Some juxtapositions are clearly wrong, and some are unexpectedly strong. Both outcomes are useful: they accelerate editing intuition and story discovery.

### What Already Works Well

- Randomized playback creates quick adjacency tests across many clips.
- Global clip length and source sectioning support structured experimentation.
- Layering and effect chains support early visual direction finding.
- Output can be reviewed immediately for candidate edit ideas.

### Gaps

- Per-layer rotation controls are missing. Rotate in 90-degree increments per layer would be nice. Consider other options.
- Rendering multiple clips in sequence, including transitions between clips, is still missing as an integrated UI workflow.
- No clear playback playhead indicator in layer scrubbing/timeline views.
- No quick, intuitive frame-by-frame stepping workflow.
- Missing a quick way (menu and/or keyboard based) for setting in/out-point of clips or global
- Global clip-length behavior is asymmetrical: reducing global length appears to reduce effective layer selection lengths, while increasing it currently leaves layer selections unchanged. Try-out global clip length expansion also by default expanding the length of all layers.

## Use Case 3: Create Shorts for Social Media

### Scenario

Start from a recently shot clip available locally or in Apple Photos, process it in Hypnograph, and export a short expressive piece for Instagram Story/Reel style posting.

### Status

This is one of the better-provisioned workflows in the current beta, but it is intentionally a lower priority than personal archive exploration and post-shoot discovery.

## Capture Plan (Screenshots + Short Screencasts)

For the collaborators homepage, prioritize showing flow, not just UI chrome.

- 1 short screencast (20-35s): first-run path from launch -> Photos permission -> randomized playback.
- 1 short screencast (20-35s): post-shoot discovery session showing fast clip juxtapositions.
- 1 short screencast (15-25s): live curation during playback (favorite, exclude, mark for deletion).
- 3 still screenshots: playback canvas, source/library context, and export-ready/social result.

This set is enough to communicate product intent quickly while keeping the page lightweight.
