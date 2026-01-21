---
created: 2026-01-20
status: Draft (refactor needed)
---

# Smart Framing (Human Centering): Overview

Goal: when a *source* is being mapped into the **output frame** (via `SourceFraming.fill`), detect a human (face/body) and bias the crop so the subject stays comfortably in-frame (head visible, body preferred) **without revealing empty edges**.

This is primarily a **framing/cropping** concern, not an effect, and should be expressed as a **render pipeline hook** so the implementation is optional, swappable, and well-contained.

Non-goal: a display/window-global “smart framing” layer. If we do anything that changes framing over time (“monitoring” / re-centering), it must happen in the same render path used by Preview *and* Export so what you see is what you render.

## Why this project exists

Today, many sources are portrait-oriented (or portrait-like compositions) but displayed in a landscape output. `fill` cropping often defaults to “center crop”, which frequently cuts off heads or frames subjects awkwardly.

Desired behavior:
- If a subject is detected and there is slack on an axis after scaling (usually vertical slack in portrait→landscape), shift the crop to keep the head in-frame and show more body.
- Prefer stable behavior (no jitter) and predictable bounds (no blank edges).
- Work for still images and videos (initial sampling is OK; continuous tracking is optional).

## Current status (what exists today)

Some prototype behavior exists in `main`, but it is currently split across multiple layers:

- Renderer-time detection and per-layer bounds plumbing (used to bias `SourceFraming.fill`).
- Preview-time “monitoring” via `PlayerView.contentFocus` (window/display-level framing), which is **not export-parity** and is therefore a smell.

The behavior is valuable, but the implementation shape needs to change so Preview and Export share a single framing decision path.

## Dolphin Diagrams

### NOW (current main)

```mermaid
flowchart LR
  subgraph NOW["NOW (current main)"]
    A["Settings.sourceFraming\n(Hypnograph)"] --> B["RenderEngine / CompositionBuilder\n(HypnoCore)"]
    B --> C["HumanRectanglesFraming (Vision)\n(HypnoCore/Renderer/Analysis)"]
    C --> D["RenderInstruction.layerPersonBounds\n(plumbed through AVVideoComposition)"]
    D --> E["FrameCompositor\n(HypnoCore)"]
    E --> F["RendererImageUtils.applySourceFraming(..., personBounds)\n(per-source crop bias)"]

    P["PreviewPlayerView\n(Hypnograph)"] --> C
    P --> Q["PlayerView.contentFocus + timer\n(window/display-level recentering)\nNOT export-parity (smell)"]
  end
```

### TARGET (framing hooks; Preview == Export)

```mermaid
flowchart LR
  subgraph TARGET["TARGET (framing hooks; Preview == Export)"]
    A2["Settings.smartFramingMode\nOff / HumanCentering"] --> H["RenderEngine.Config (or RendererHooks)\nprovides FramingHook"]
    H --> I["FramingHook.framingBias(request)\n(HypnoCore/Renderer/Framing/Core)"]
    I --> J["HumanCenteringFramingHook\n(HypnoCore/Renderer/Framing/Implementations/HumanCentering)\nVision + caching + heuristics"]
    I --> K["RendererImageUtils.applySourceFraming(..., bias)\n(single apply site; per-source fill)"]
    K --> L["FrameCompositor / Live / Export / Preview\n(all share the same path)"]

    J --> K
    M["PlayerView.display\n(no contentFocus smart framing)"] -.-> L
  end
```

## What’s wrong with the current shape (why it shouldn’t merge yet)

The behavior is useful, but the implementation is not sufficiently encapsulated and does not guarantee Preview == Export:
- Logic is spread across renderer utilities, composition building, compositing, and preview playback glue.
- Preview currently applies additional display/window-level framing (`contentFocus`) that export does not have.
- There is not yet a coherent “hook API” for framing decisions that future features can reuse.
- Enable/disable is not expressed at a clear pipeline boundary.
- Caching / invalidation policy is not expressed as a dedicated module with clear ownership.

## Target architecture (what we want before merging)

Introduce a framing hook layer in `HypnoCore/Renderer` similar in spirit to the Effects subsystem, but tailored to cropping decisions:

- `HypnoCore/Renderer/Framing/Core/`
  - `FramingRequest` (inputs: source framing mode, output size/aspect, source extent/transform, time, sourceIndex, etc.)
  - `FramingBias` (outputs: anchor/bounds + axis preferences, headroom, target position)
  - `FramingHook` protocol + default no-op implementation
  - A small registry/wiring surface (either per-render config or a renderer-scoped shared hook)
- `HypnoCore/Renderer/Framing/Implementations/HumanCentering/`
  - Vision integration, heuristics/tuning, and caching (entirely self-contained)

Renderer integration should become a single call-site:
- `FrameCompositor` (or `RendererImageUtils.applySourceFraming(...)`) asks for an optional `FramingBias` and applies it during *per-source* `fill` crop translation.

If we keep any time-varying behavior (“monitoring” / re-centering for video), it must be:
- implemented inside the `FramingHook` (time-aware request → bias), and
- applied in the compositor so **Preview, Live, Export** all use the same logic.

The display layer (`PlayerView.contentFocus`) should not be part of smart framing, since it cannot be export-parity.

## “Definition of ready to merge”

Before merging to `main`, we want:
- A `FramingHook` API that is generic (not human-specific) and can support future framing policies.
- Human centering implemented entirely inside `Framing/Implementations/HumanCentering`.
- Minimal touchpoints in the renderer (ideally 1–2 call sites).
- Clear enable/disable surface (setting/flag) and predictable defaults.
- Basic performance guardrails (downscaled analysis, caching) and safe fallbacks.
