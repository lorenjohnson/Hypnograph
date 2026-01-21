# Hypnograph — Mission

## What this product is

Hypnograph is a macOS application for **virtual, real-time audiovisual composition and performance**.

At its core, Hypnograph is an **autonomous visual instrument**:
- is given access to a photo/video archive
- when it opens and immediately begins generating output to make accessing one's past archive a visceral and immediate experience which can happen without management or curation.
- it is a randomizing Video Sequencer...

No setup, planning, or compositional intent is required to begin.
Something happens by default.

This “no-thinking” access to a personal archive is a primary entryway into the work.

---

## Core experience arc

1. **Immediate generation**
   - On first launch, after permission is granted to Apple Photos or folders,
     Hypnograph begins playing with the archive automatically.
   - Selection is random by default.
   - The user encounters their own past without having to choose it.

2. **Deepening into composition**
   - The user can gradually intervene:
     - shaping timing,
     - applying effects,
     - constraining sources,
     - saving evolving states (“hypnograms”).
   - Composition emerges from interaction, not premeditation.

3. **Live and witnessing**
   - The system supports live performance:
     - external displays,
     - real-time control,
     - intentional presentation.
   - Live is not separate from the archive; it is a way of
     **digesting, integrating, and re-seeing personal material**.

4. **Sharing and aesthetic witnessing**
   - Output may be rendered, shown live, or shared.
   - The act of showing is considered part of the work:
     witnessing, being witnessed, and recontextualizing memory.

---

## Core design principles

- **Autonomous by default**
  - The system acts first.
  - The user responds.

- **Archive as living material**
  - Photos and videos are not static assets but an active, generative field.
  - The app privileges encounter over curation.

- **Live-first**
  - Real-time stability and low latency are non-negotiable.
  - Input must never block rendering.

- **Ritual, not productivity**
  - The app is designed to support presence, digestion, and aesthetic attention,
    not optimization or throughput.

- **Single-author instrument**
  - Built for one operator at a time.
  - No collaboration, syncing, or background automation.

---

## High-level architecture

- **Swift / SwiftUI + AppKit hybrid**
  - SwiftUI for structure and state binding.
  - AppKit for windowing, input, and performance-critical paths.

- **Modular modes**
  - Multiple modules share infrastructure but differ in behavior.
  - Only one module is active at a time.

- **Explicit state**
  - Application state is centralized and observable.
  - Rendering, input, persistence, and archive access are separated concerns.

- **Real-time rendering pipeline**
  - Frame-based, time-driven.
  - Supports live preview, external display, and offline rendering.

---

## Input and interaction

- Keyboard shortcuts are primary.
- Game controllers may be used for expressive control.
- Input handling must be:
  - deterministic,
  - low-latency,
  - and never interrupt rendering.

---

## Persistence and files

- Hypnograms are saved compositions (*.hypno or *.hypnogram files).
- Settings and window state are persisted explicitly.
- Files may be opened via:
  - double-click,
  - drag-and-drop,
  - or menu actions.

---

## Non-goals

- No collaborative editing.
- No cloud services.
- No AI-driven generative decision making.
- No hidden background processes.
- Generally no generative content, the point is to entropy one's own archive, to give the real experience of it aging, fading in the past

---

## Guidance for code generation

When generating or modifying code:

- Pay attention to the the core app architecture. Many of the components here are or will be shared by an ecosystem of products, and this is the primary one where we are developing these systems (the media library, the rendering engine, the effects system, the windowing and player systems, etc)
- Preserve the autonomous, generative default behavior.
- Do not require user intent before visible output.
- Prefer explicit state over clever abstraction.
- Avoid speculative features.
- Ask before large refactors.
- Treat performance regressions as critical bugs.

The goal is **trustworthy, stable, expressive software**
that helps users encounter and integrate their own material.

## Differentiators

- **Effect-first workflow** - Unique effects (datamosh, pixel sort, block propagation) not available in mainstream tools
- **Hypnogram format** - Recipes saved as PNG with embedded metadata, shareable and resumable
- **Live-oriented** - Designed for live use with quick keyboard/controller shortcuts
- **Apple-native** - Pure Swift/Metal, no external dependencies, leverages macOS capabilities

## Modules

| Module | Purpose |
|--------|---------|
| **Dream** | Primary composition mode with Montage and Sequence sub-modes |
| **Divine** | Card-based visual oracle / exploration interface |
| **Live Display** | Secondary window for live output during performances |

## Success Metrics

- Stable 30+ fps during live performance
- Sub-second effect switching
- Successful exports without preview state contamination

