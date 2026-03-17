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

### Why This Matters

- It turns static archives into living sequences with rhythm, contrast, and emotional texture.
- It supports rediscovery, not just retrieval: less catalog browsing, more felt meaning.
- It creates a path from reflection into authorship, where personal memory can be shaped into new visual forms.

## Use Case 2: Create Shorts for Social Media

### Scenario

Start from a recently shot clip available as a local file or in Apple Photos, bring it into Hypnograph, process it with effects/montage, and export a short expressive clip for Instagram Story/Reel style postings.

### What Already Works Well

- Clip length can be determined globally.
- A specific section of source clip can be selected and used.
- Multiple effects can be stacked for rich output.
- Multiple clips can be composited/montaged together.
- Existing effects/effects engine already provides a strong range for experimental visual output.

### Gaps

- Per-layer rotation controls are missing. Rotate in 90-degree increments per layer would be nice. Consider other options.
- Rendering multiple clips in sequence, including transitions between clips, is still missing as an integrated UI workflow.
- No clear playback playhead indicator in layer scrubbing/timeline views.
- No quick, intuitive frame-by-frame stepping workflow.
- Missing a quick way (menu and/or keyboard based) for setting in/out-point of clips or global
- Global clip-length behavior is asymmetrical: reducing global length appears to reduce effective layer selection lengths, while increasing it currently leaves layer selections unchanged. Try-out global clip length expansion also by default expanding the length of all layers.
