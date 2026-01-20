# Export Clip History (FCPXML): Overview

**Created**: 2026-01-19  
**Status**: Planning / Review  

## Goal

Add a menu command that exports the user’s **Clip History** into an **FCPXML** timeline that can be imported into an NLE (initially targeting Final Cut Pro and DaVinci Resolve).

- Menu placement: **Hypnograph app menu (leftmost)** → below **Clear Clip History** → **Export Clip History (FCPXML)**
- Default export behavior:
  - **No transitions** between history entries (hard cuts).
  - **Original media references** (no rendering).
  - If a History clip is a montage (multiple sources), export **stacked layers** and apply a configurable blend mode for overlaps.

## Primary Requirements

1) **Original media references**
- Export should reference original media files directly (NLE imports via `file://` URLs).
- For **Apple Photos** items, export should reference the **original file in place on disk** when possible.

2) **Use the exact selected in/out per source**
- Every exported source must preserve the same begin/end points the user selected in the history item:
  - `VideoClip.startTime` becomes the exported clip start/in-point.
  - `VideoClip.duration` becomes the exported clip duration (trim length).
- No “helpful” retiming/auto-trimming in v1 unless explicitly configured.

3) **Overlapping blend mode is configurable**
- Export code takes a configurable blend mode string for overlapping sources (default `"screen"`).
- This blend mode is applied to montage layers (typically source index ≥ 1), unless a future revision exports per-source blend modes from `HypnogramSource.blendMode`.

4) **Transitions are optional**
- Default is **none**.
- Plan should include what it would take to support:
  - Fade (to/from black) and/or
  - Dissolve (cross dissolve) between adjacent history clips.

5) **User-facing command**
- Appears as: **Export Clip History (FCPXML)** under the Hypnograph menu, below **Clear Clip History**.
- Opens a save panel to pick destination `.fcpxml`.

## Current Data Model (what we export)

Clip history is persisted at:
- `Environment.clipHistoryURL` → JSON `ClipHistoryFile`:
  - `clips: [HypnogramClip]`
  - `currentClipIndex: Int`

Each `HypnogramClip` contains:
- `sources: [HypnogramSource]` (montage layers)
- `targetDuration: CMTime`
- `playRate: Float`

Each `HypnogramSource` contains:
- `clip: VideoClip`:
  - `file: MediaFile` (origin)
  - `startTime: CMTime`
  - `duration: CMTime`
- `transforms: [CGAffineTransform]` (user transforms)
- `blendMode: String?` (currently used by the renderer/compositor)

## What “Export Clip History” means (v1 definition)

Treat the clip history as a linear timeline:
- One history item = one timeline segment of length `HypnogramClip.targetDuration` (or a reviewed variant if `playRate` should affect timeline duration).
- Each history item exports:
  - base layer: source 0 (normal)
  - additional montage layers: sources 1…N stacked above, with blend mode default `"screen"` (configurable)

Within each history segment:
- Each source’s **in/out** must match what was selected:
  - Start = `HypnogramSource.clip.startTime`
  - Duration = `HypnogramSource.clip.duration`
- If `HypnogramClip.targetDuration` is longer than a source’s selected duration, the exporter must choose a policy (see Implementation Plan):
  - loop/repeat the source, or
  - freeze last frame / let it end (gap), or
  - clamp the segment duration to the shortest layer

## Apple Photos “original file in place” notes (important)

Photos assets are stored as `MediaSource.external(identifier: localIdentifier)`.

To satisfy “point to the original file in place on disk”, the exporter must be able to resolve a stable `file://` URL:
- Images: typically available via `PHContentEditingInput.fullSizeImageURL`.
- Videos: sometimes available if `requestAVAsset` yields `AVURLAsset(url: fileURL)`.

If PhotoKit cannot provide a stable file URL, the plan must explicitly decide how hard we push for “in place”:
- **Official approach (preferred)**: resolve via PhotoKit to a stable file URL.
- **Bruteforce approach (possible but risky)**: locate the original inside the Photos Library bundle by scanning/indexing.
  - This can work for the common local-library case but is brittle across macOS/Photos versions and may behave differently with iCloud-only assets.

v1 policy should be **strict**:
- If a Photos asset cannot be resolved to a stable in-place `file://` URL, fail export with a clear error listing unresolved identifiers.

## Non-goals for v1

- Exporting Hypnograph effects/effect chains to NLE equivalents.
- Perfect fidelity of custom blend modes across every NLE.
- Exporting metal shader transitions (Scoot/Shuffle/etc.) to NLE transitions.
- Audio leveling, fades, or mixdown (unless explicitly added as an option later).

## Output Format Choice

Primary: **FCPXML** (pragmatic import path for Final Cut Pro and generally workable with Resolve).

Possible future additions:
- EDL (cuts-only fallback; cannot represent montage layers + Screen).
- OTIO as an intermediate representation (requires adapter for most NLE import workflows).
