---
created: 2026-01-20
status: Draft
---

# Smart Framing (Human Centering): Implementation Planning

This plan describes how to move from the current prototype (on `feature/smart-framing-human-centering`, split from `feature/metal-playback-pipeline`) to a mergeable, well-encapsulated feature on `main`.

## Phase 0 — Name the hook surface + decide wiring

Decide the canonical place for render-lifecycle hooks.

Recommended: introduce a renderer-scoped hooks surface (separate from `HypnoCoreHooks`, which is currently media/export-focused).

Decisions:
- Do we wire hooks via:
  - A) `RenderEngine.Config` (explicit, testable, instance-based), or
  - B) `RendererHooks.shared` (global, simple, matches current `HypnoCoreHooks` style)?
- What is the initial scope:
  - per-source framing (v1),
  - optional global framing (v2)?

Deliverable:
- A one-page “Hook Naming + Wiring” note in this project folder (can be folded into this doc later).

## Phase 1 — Define the generic framing API (Core)

Add `HypnoCore/Renderer/Framing/Core` with:
- `FramingRequest`
  - `sourceFraming` (`fill` / `fit`)
  - `outputSize` / output aspect ratio
  - `sourceExtent` (post-transform)
  - `sourceIndex` (+ stable source id if available)
  - `time` (for video sampling/tracking)
  - optional hints (axis preference, “no blank edges” contract)
- `FramingBias`
  - anchor point (normalized)
  - optional bounds rect (normalized)
  - axis constraints (`verticalOnly` / `horizontalOnly` / `both`)
  - “headroom” / target placement parameters
- `FramingHook` protocol:
  - `func framingBias(for request: FramingRequest) -> FramingBias?`
- Default no-op implementation.

Acceptance:
- Renderer can call the hook without importing Vision.
- No human-specific naming in the core API.

## Phase 2 — Move crop math behind the hook (single call site)

Refactor `RendererImageUtils.applySourceFraming` so:
- It builds a `FramingRequest` when `sourceFraming == .fill`
- It asks the hook for an optional `FramingBias`
- It applies the bias when computing the crop translation
- If bias is nil, behavior is identical to today’s centered crop

Acceptance:
- Crop behavior remains deterministic and edge-clamped by default (“no blank edges”).
- The renderer does not need to know anything about humans/faces.

## Phase 3 — Implement HumanCentering as a FramingHook

Add `HypnoCore/Renderer/Framing/Implementations/HumanCentering`:
- Vision analysis (faces + human rectangles)
- Scoring/selection rules (prefer face anchor, use human bounds when available)
- Axis policy defaults (usually vertical-only, but computed based on slack and/or request hints)
- Tuning parameters (target head position, headroom factor, confidence/area thresholds)
- Caching:
  - still images: cache by source id + transforms + output aspect (or request signature)
  - video: cache by source id + sampled time(s) + request signature

Acceptance:
- All Vision code lives under `Framing/Implementations/HumanCentering`.
- The rest of the codebase only references `FramingHook` and request/bias types.

## Phase 4 — Replace prototype plumbing with the hook implementation

Remove prototype-specific wiring that spread across:
- composition builder sampling helpers
- render instruction “person bounds” plumbing
- preview player “tracking” that calls directly into analysis helpers

Replace with:
- A single hook registration + an enable/disable toggle.

Decision point:
- Keep preview-time continuous tracking?
  - If yes, it should call the same `HumanCentering` module via a “frame-based request” adapter.
  - If no, rely on initial sampling/caching (cheaper, more stable).

Acceptance:
- “Smart framing” can be toggled without touching rendering internals.
- Feature code lives in one module/folder.

## Phase 5 — UX + settings surface

Add a user-facing setting (or a feature flag) so this is not “always on” by default until validated:
- Mode: Off / Human Centering (prototype)
- Optional advanced controls later (strength/headroom/axis preference)

Acceptance:
- Defaults are conservative.
- Behavior is predictable (no blank edges; stable framing).

## Phase 6 — Validation, performance, and merge readiness

Validation checklist:
- Portrait sources displayed in landscape output: heads aren’t routinely cut.
- Landscape sources displayed in portrait output: bias works when slack exists.
- Multi-layer montages: framing stays per-source and does not behave erratically.
- Performance: analysis is downscaled and cached; no obvious UI stalls.
- Regression safety: when Vision fails, fall back to centered crop (no crashes).

Merge readiness:
- Hook API is documented.
- Implementation is isolated.
- Minimal diffs outside `Framing/*` and the hook call site.
