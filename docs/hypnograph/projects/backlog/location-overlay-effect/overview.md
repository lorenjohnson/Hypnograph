# Location Overlay Effect: Overview

**Created**: 2026-01-21  
**Status**: Proposal / Planning  
**Architecture**: Uses the existing per-source effects pipeline (Effect chains + RenderContext)  

## Goal

Add a new **Location Overlay** effect that reads an asset’s geographic location (when available) and overlays a human-readable location label on top of the rendered layer.

Phase 1 ships with a deterministic, non-ambiguous coordinate display (lat/long short form). Later phases add reverse-geocoded place names and typography controls.

## Problem

Hypnograph often works with media whose meaning is tied to where it was captured. Today, location metadata (when present in Apple Photos assets) is not surfaced in the render output, and there’s no simple “stamp the location” effect.

## Desired UX (high-level)

- The user adds **Location Overlay** to a layer’s effect chain.
- If the source has location metadata:
  - show a small text overlay (default position + style) on that layer.
- If location is missing or unavailable:
  - render unchanged (no overlay).

## Phase 1 scope (MVP)

### Source support
- Apple Photos assets (`MediaSource.external(identifier:)`) only.
- File-based assets (URL sources) are explicitly deferred (Phase 1.5+).

### Display format
Overlay a short-form coordinate label, e.g.:
- `32° 18' N 122° 36' W`

Notes:
- This is “Degrees + Minutes” with hemisphere letters.
- Seconds are omitted for readability; rounding policy must be deterministic (see Implementation Plan).

### Integration constraint
The effect should use the **existing effects hook architecture**:
- Effects run inside `EffectChain.apply(to:context:)`.
- Per-source effects are applied in the compositor with a `RenderContext` whose `sourceIndex` is set.
- External source resolution is done via `HypnoCoreHooks` (wired up by `ApplePhotosHooks`).

## Phase 2 scope

Add a parameter to choose between:
- **Coordinates** (Phase 1 behavior)
- **Place name** via reverse geocoding (e.g. `Longview, WA, USA`)

Requirements:
- If reverse geocoding fails or is rate-limited, fall back to coordinates.
- Must be cached so we do not geocode per frame.

## Phase 3 scope

Add typography controls:
- Font size: either a small/medium/large enum or a direct point-size parameter (decision TBD).
- Optional: font family/face selection (if it fits the current effect parameter UI model).

## Phase 4 exploration

Evolve toward a multi-modal “Info/Text Overlay” effect:
- A single overlay effect with a content picker / token selector for:
  - coordinates (lat/long)
  - place name
  - capture time/date
  - (later) custom text / other metadata

This phase likely wants a reusable “dynamic text source” abstraction (similar to the note in `TextOverlayEffect` about transitioning to a `TextSource` type).

## Non-goals (v1)

- Rendering a map tile / embedded map (static or interactive).
- Editing overlay position, background box, shadows, or per-corner placement controls.
- Reading file-based EXIF/QuickTime GPS metadata (defer until Phase 1 is stable).

## Risks / unknowns

- **Context plumbing**: Effects currently know `sourceIndex` but may not know the source identifier; we likely need to pass a stable identifier into `RenderContext` or provide a query hook.
- **Asynchrony**: Photos + reverse geocoding are async. The effect pipeline is synchronous per-frame; we need a prefetch/cache strategy so export is deterministic.
- **Privacy/availability**: Many assets do not have location, or location may be stripped; the effect must degrade gracefully.

