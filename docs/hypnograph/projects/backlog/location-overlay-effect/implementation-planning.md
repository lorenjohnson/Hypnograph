# Location Overlay Effect: Implementation Planning

**Created**: 2026-01-21  
**Status**: Draft

This plan is scoped to ship a reliable Phase 1 and then incrementally add richer location display options without destabilizing the renderer.

## Key design decisions (make these explicit early)

1) **Where does the effect get “which asset am I rendering”?**
- Today, per-source effects only get the rendered `CIImage` plus a `RenderContext` with `sourceIndex` set (no URL / no Photos identifier is currently passed through). See `HypnoCore/Renderer/Core/RenderContext.swift:18` and where the compositor creates the context at `HypnoCore/Renderer/Core/FrameCompositor.swift:184`.
- Effects already receive `RenderContext.sourceIndex`.
- We likely need one of:
  - Add a stable `sourceIdentifier` (or `MediaSource`) field to `RenderContext`, set by the compositor while rendering each source, or
  - Add a `RenderContext` callback (e.g. `sourceInfo(for:)`) that the compositor populates.

**Recommendation:** do *not* try to pass a `PHAsset` instance into the effect. Effects live in HypnoCore’s synchronous render pipeline, and we want them to stay platform-agnostic and deterministic for export. Passing `PHAsset` would couple the effect to PhotoKit types/lifetimes and still wouldn’t solve the “don’t do heavyweight lookups per frame” problem. Prefer passing a stable identifier (e.g. Photos `localIdentifier`) or `MediaSource`, then resolving location via hooks + caching.

2) **When do we resolve location?**
- Preview can tolerate “appears after a moment” behavior; export should be deterministic.
- Preferred pattern:
  - Resolve once per source per clip (cache), not per frame.
  - Prefer resolving during **source loading / composition build** (async, off the render loop) so the effect stays synchronous.
  - Preflight export to ensure all needed overlay strings are resolved before render begins (or choose a strict fallback policy).

3) **What’s the Phase 1 coordinate format?**
- Decide a deterministic rounding rule:
  - round to nearest minute, or
  - truncate to minute (stable but biased), or
  - include seconds (more precise but noisier).
- MVP recommendation: **round to nearest minute** for legibility.

## Phase 1 (MVP): Apple Photos coordinate overlay

### A) Hook + context plumbing
- Extend the effects runtime context so an effect can identify the current source beyond its index:
  - Add `sourceIdentifier: String?` (or `source: MediaSource?`) to `RenderContext`.
  - Populate it in the compositor when applying per-source effects.

### B) External location resolution hook
- Extend `HypnoCoreHooks` with an optional async hook (naming TBD):
  - `resolveExternalLocation: ((String) async -> CLLocation?)?` or a lightweight coordinate return type.
- Wire it up in `ApplePhotosHooks`:
  - Fetch `PHAsset` for the identifier.
  - Return `PHAsset.location` if present.

### B.1) Prefer fetching location at load/build time (not in the effect init/apply path)
- Best place to fetch location is when we already resolve the external source during composition build:
  - `SourceLoader.loadVideoSource` / `SourceLoader.loadImageSource` already have the external identifier (async) and run off the render loop.
- Two viable “plumbing” patterns:
  1) Enrich `LoadedSource` with `location` (and later `captureDate`) and thread it through to the compositor via `RenderInstruction`.
  2) Keep `LoadedSource` unchanged and build a parallel `SourceMetadata` table (by sourceIndex) during `CompositionBuilder.buildMontage`, then attach it to `RenderInstruction`.

Either way, the effect reads already-available metadata synchronously (no PhotoKit calls during `apply(to:context:)`).

### C) The new effect type
- Add `LocationOverlayEffect` as a per-source effect (registered in `EffectRegistry`).
- Phase 1 behavior:
  - If no location: return the original image.
  - If location exists: render a fixed-style label on top of the image.
- Rendering implementation should reuse existing text overlay machinery if possible (e.g. the drawing approach in `TextOverlayEffect`) to avoid a brand-new rendering subsystem.

### D) Caching strategy
- Cache the formatted coordinate string per source identifier:
  - In the effect instance (per-layer) or via a small shared cache keyed by identifier.
- Ensure `reset()` behavior clears per-clip ephemeral state but doesn’t thrash caches unnecessarily.

### E) Validation checklist
- Apple Photos video + still image sources:
  - With location → overlay appears and stays stable.
  - Without location → no overlay, no errors.
- Preview vs export:
  - Overlay matches between both (same text).
- Performance:
  - No per-frame Photos fetch calls; only once per source/clip.

## Phase 2: Place name mode (reverse geocode)

### A) Effect parameter
- Add an effect param (choice) to switch:
  - `coordinates` (default)
  - `placeName`

### B) Reverse geocoding
- Use `CLGeocoder.reverseGeocodeLocation` to produce a short string.
- Decide a stable formatting policy for the placemark components:
  - recommended: `locality, administrativeArea, country` (when available).

### C) Rate limiting + fallback
- Cache results by coordinate (or by identifier).
- If geocoder fails:
  - fall back to coordinates.

## Phase 3: Typography controls

### A) Font size
- Decide UI model:
  - choice enum (`small`, `medium`, `large`), or
  - float point size slider.
- Add parameter spec accordingly and wire into text drawing.

### B) Optional font family/face
- If we support it, prefer a constrained list (avoid arbitrary font string entry).

## Phase 4: Multi-modal “Info Overlay” exploration

Goal: a single overlay effect that can choose from multiple metadata-backed tokens:
- location coordinates
- location place name
- capture time/date
- (later) user-provided custom text

This likely wants a generalized “dynamic text source” model so that multiple effects can reuse the same metadata lookups and caching logic.

## Open questions

- Should the overlay be per-source only, or also usable as a global effect (after compositing)?
- Default placement: bottom-left vs bottom-right; should that become a param later?
- Styling: do we want stroke/shadow/background plate for legibility against bright footage?
- Export policy: if location lookup fails during export, do we omit overlay or fail the render?
- Persistence policy: do we ever persist location into the recipe JSON, or keep it strictly ephemeral (resolved from source each session)?
