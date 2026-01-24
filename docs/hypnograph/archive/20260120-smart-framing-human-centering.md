---
created: 2026-01-20
updated: 2026-01-21
status: Implemented (hook-based; tuning TBD)
---

# Smart Framing (Human Centering)

## Overview

Goal: when a *source* is being mapped into the **output frame** (via `SourceFraming.fill`), detect a human (face/body) and bias the crop so the subject stays comfortably in-frame (head visible, body preferred) **without revealing empty edges**.

This is primarily a **framing/cropping** concern, not an effect, and should be expressed as a **render pipeline hook** so the implementation is optional, swappable, and well-contained.

Non-goal: a display/window-global "smart framing" layer. If we do anything that changes framing over time ("monitoring" / re-centering), it must happen in the same render path used by Preview *and* Export so what you see is what you render.

## Why this project exists

Today, many sources are portrait-oriented (or portrait-like compositions) but displayed in a landscape output. `fill` cropping often defaults to "center crop", which frequently cuts off heads or frames subjects awkwardly.

Desired behavior:
- If a subject is detected and there is slack on an axis after scaling (usually vertical slack in portrait→landscape), shift the crop to keep the head in-frame and show more body.
- Prefer stable behavior (no jitter) and predictable bounds (no blank edges).
- Work for still images and videos

## Current status (what exists today)

Smart framing is implemented as a **render-parity** system:

- A `FramingHook` runs in the compositor for per-source `SourceFraming.fill`.
- The default `HumanCenteringFramingHook` uses Vision-based detection and caches results per render session/time bucket.
- Preview and Export share the same framing decision path (no preview-only display/window framing).

---

## Target architecture

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

If we keep any time-varying behavior ("monitoring" / re-centering for video), it must be:
- implemented inside the `FramingHook` (time-aware request → bias), and
- applied in the compositor so **Preview, Live, Export** all use the same logic.

The display layer (`PlayerView.contentFocus`) should not be part of smart framing, since it cannot be export-parity.

---

## Implementation Plan

This plan describes how to move from the current prototype to a mergeable, well-encapsulated feature.

Core requirement: Preview and Export must share the same framing logic. Any "monitoring" / re-centering behavior must run in the render path (per-source `SourceFraming.fill`), not in display/window-global framing.

### Phase 0 — Name the hook surface + decide wiring

Decide the canonical place for render-lifecycle hooks.

Recommended: introduce a renderer-scoped hooks surface (separate from `HypnoCoreHooks`, which is currently media/export-focused).

Decisions:
- Do we wire hooks via:
  - A) `RenderEngine.Config` (explicit, testable, instance-based), or
  - B) `RendererHooks.shared` (global, simple, matches current `HypnoCoreHooks` style)?
- What is the initial scope:
  - per-source framing (v1),
  - optional global framing (v2)?

### Phase 1 — Define the generic framing API (Core)

Add `HypnoCore/Renderer/Framing/Core` with:
- `FramingRequest`
  - `sourceFraming` (`fill` / `fit`)
  - `outputSize` / output aspect ratio
  - `sourceExtent` (post-transform)
  - `sourceIndex` (+ stable source id if available)
  - `time` (for video sampling/tracking)
  - optional hints (axis preference, "no blank edges" contract)
- `FramingBias`
  - anchor point (normalized)
  - optional bounds rect (normalized)
  - axis constraints (`verticalOnly` / `horizontalOnly` / `both`)
  - "headroom" / target placement parameters
- `FramingHook` protocol:
  - `func framingBias(for request: FramingRequest) -> FramingBias?`
- Default no-op implementation.

Acceptance:
- Renderer can call the hook without importing Vision.
- No human-specific naming in the core API.

### Phase 2 — Move crop math behind the hook (single call site, render-parity)

Refactor `RendererImageUtils.applySourceFraming` so:
- It builds a `FramingRequest` when `sourceFraming == .fill`
- It asks the hook for an optional `FramingBias`
- It applies the bias when computing the crop translation
- If bias is nil, behavior is identical to today's centered crop

Acceptance:
- Crop behavior remains deterministic and edge-clamped by default ("no blank edges").
- The renderer does not need to know anything about humans/faces.
- No display/window-level framing is required to get the behavior in Preview.

### Phase 3 — Implement HumanCentering as a FramingHook

Add `HypnoCore/Renderer/Framing/Implementations/HumanCentering`:
- Vision analysis (faces + human rectangles)
- Scoring/selection rules (prefer face anchor, use human bounds when available)
- Axis policy defaults (usually vertical-only, but computed based on slack and/or request hints)
- Tuning parameters (target head position, headroom factor, confidence/area thresholds)
- Caching:
  - still images: cache by source id + transforms + output aspect (or request signature)
  - video: cache by source id + sampled time(s) + request signature (time-bucketed so Export and Preview make the same decisions)

Acceptance:
- All Vision code lives under `Framing/Implementations/HumanCentering`.
- The rest of the codebase only references `FramingHook` and request/bias types.

### Phase 4 — Replace prototype plumbing with the hook implementation

Remove prototype-specific wiring that spread across:
- composition builder sampling helpers and/or early-frame analysis
- render instruction "person bounds" plumbing (`layerPersonBounds`)
- preview player "tracking" that calls directly into analysis helpers

Replace with:
- A single hook registration + an enable/disable toggle.

Decision point:
Keep time-varying framing for video ("monitoring" / re-centering)?
- If yes, it must run inside the `FramingHook` and be driven by `FramingRequest.time` so Preview and Export behave identically.
- If no, rely on initial sampling/caching (cheaper, more stable) while still staying render-parity.

### Phase 5 — UX + settings surface

Add a user-facing setting (or a feature flag) so this is not "always on" by default until validated:
- Mode: Off / Human Centering (prototype)
- Optional advanced controls later (strength/headroom/axis preference)

Acceptance:
- Defaults are conservative.
- Behavior is predictable (no blank edges; stable framing).
- This setting affects per-source `SourceFraming.fill` only (not window fill / display framing).

### Phase 6 — Validation, performance, and merge readiness

Validation checklist:
- Portrait sources displayed in landscape output: heads aren't routinely cut.
- Landscape sources displayed in portrait output: bias works when slack exists.
- Multi-layer montages: framing stays per-source and does not behave erratically.
- Performance: analysis is downscaled and cached; no obvious UI stalls.
- Regression safety: when Vision fails, fall back to centered crop (no crashes).

Merge readiness:
- Hook API is documented.
- Implementation is isolated.
- Minimal diffs outside `Framing/*` and the hook call site.

---

## Definition of ready to merge

Before merging to `main`, we want:
- A `FramingHook` API that is generic (not human-specific) and can support future framing policies.
- Human centering implemented entirely inside `Framing/Implementations/HumanCentering`.
- Minimal touchpoints in the renderer (ideally 1–2 call sites).
- Clear enable/disable surface (setting/flag) and predictable defaults.
- Basic performance guardrails (downscaled analysis, caching) and safe fallbacks.
