---
created: 2026-01-20
status: Prototype (feature branch)
branch: feature/smart-framing-human-centering
---

# Smart Framing (Human Centering): Overview

Goal: when a source is being mapped into the output frame (typically `SourceFraming.fill`), detect a human (face/body) and bias the crop so the subject stays comfortably in-frame (head visible, body preferred) **without revealing empty edges**.

This is primarily a **framing/cropping** concern, not an effect, and should be expressed as a **render pipeline hook** so the implementation is optional, swappable, and well-contained.

## Why this project exists

Today, many sources are portrait-oriented (or portrait-like compositions) but displayed in a landscape output. `fill` cropping often defaults to “center crop”, which frequently cuts off heads or frames subjects awkwardly.

Desired behavior:
- If a subject is detected and there is slack on an axis after scaling (usually vertical slack in portrait→landscape), shift the crop to keep the head in-frame and show more body.
- Prefer stable behavior (no jitter) and predictable bounds (no blank edges).
- Work for still images and videos (initial sampling is OK; continuous tracking is optional).

## Prototype status (what exists today)

This work currently lives on the feature branch:
- `feature/smart-framing-human-centering`

This branch was split off from `feature/metal-playback-pipeline` so the metal playback work can be reviewed/merged independently.

The prototype has been iterated in-place to feel good during real use and currently includes:
- Vision-based detection using face + human rectangle observations.
- Preview-time “tracking” that periodically re-evaluates the current frame and adjusts framing (tuned for mostly vertical bias).
- Renderer-time biasing for `SourceFraming.fill` so portrait sources can crop toward heads without revealing edges.
- Video sources: early-frame sampling to seed a stable crop bias.

## What’s wrong with the current shape (why it shouldn’t merge yet)

The behavior is useful, but the implementation is not sufficiently encapsulated:
- Logic is spread across core renderer utilities, composition building, compositing, and preview playback glue.
- There is not yet a coherent “hook API” for framing decisions that future features can reuse.
- There is no clean on/off switch at the pipeline boundary (beyond editing code).
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
- `RendererImageUtils.applySourceFraming(...)` asks for an optional `FramingBias` and applies it during `fill` crop translation.

Preview-time tracking, if kept, should reuse the same “HumanCentering” implementation module (not re-implement detection logic in app code).

## “Definition of ready to merge”

Before merging to `main`, we want:
- A `FramingHook` API that is generic (not human-specific) and can support future framing policies.
- Human centering implemented entirely inside `Framing/Implementations/HumanCentering`.
- Minimal touchpoints in the renderer (ideally 1–2 call sites).
- Clear enable/disable surface (setting/flag) and predictable defaults.
- Basic performance guardrails (downscaled analysis, caching) and safe fallbacks.
