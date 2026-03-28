
# Reference: FCPXML Export

This document is technical background for the active sequences project.
It is not the canonical product spec for sequence behavior.

Use it to preserve export research and implementation notes while [index.md](./index.md) and [plan.md](./plan.md) settle the active product and UI direction.

## Current Working Assumption

If sequence export lands early, the smallest plausible path is probably a history-range-based export rather than a full timeline editor.

That assumption is intentionally provisional. If the active sequences work chooses a different model, this reference should be revisited rather than treated as binding product direction.

## Appendix A: FCPXML Research and Implementation Notes (from prior spec)

This appendix preserves and organizes deeper material from the prior export planning doc.

### A1) Data model context

Clip history persistence:
- `Environment.clipHistoryURL` -> JSON `ClipHistoryFile`
- `ClipHistoryFile.clips: [HypnogramClip]`
- `ClipHistoryFile.currentClipIndex: Int`

`HypnogramClip` carries:
- `sources: [HypnogramSource]`
- `targetDuration: CMTime`
- `playRate: Float`

`HypnogramSource` carries:
- `clip: VideoClip` (`file`, `startTime`, `duration`)
- `transforms: [CGAffineTransform]`
- `blendMode: String?`

### A2) FCPXML v1 mapping

Treat history as linear timeline segments:
- one history item = one timeline segment.
- base layer from source 0.
- additional montage layers from sources 1...N.

Per-source trim mapping:
- export start/in from `HypnogramSource.clip.startTime`
- export duration from `HypnogramSource.clip.duration`

If segment duration exceeds selected source trim, fill policy must be explicit:

```swift
enum LayerFillPolicy {
    case clampSegmentToSelectedDuration
    case loopSelectedRange
    case holdLastFrame
    case leaveGap
}
```

### A3) Proposed exporter API surface

```swift
struct FCPXMLClipHistoryExportOptions {
    var timelineName: String = "Hypnograph Clip History"
    var frameRate: Int = 30
    var renderSize: CGSize = CGSize(width: 1920, height: 1080)

    var montageBlendMode: String = "screen"
    var includeMontageLayers: Bool = true

    enum ClipDurationPolicy { case targetDuration, targetDurationAdjustedForPlayRate }
    var clipDurationPolicy: ClipDurationPolicy = .targetDuration

    enum InterClipTransition {
        case none
        case dissolve(durationSeconds: Double)
        case fadeToBlack(durationSeconds: Double)
    }
    var interClipTransition: InterClipTransition = .none

    enum PhotosResolutionPolicy {
        case requireFileURLInPlace
        case allowMaterializedCopy(exportFolderURL: URL)
    }
    var photosResolutionPolicy: PhotosResolutionPolicy = .requireFileURLInPlace
}

final class FCPXMLClipHistoryExporter {
    func export(history: ClipHistoryFile, to url: URL, options: FCPXMLClipHistoryExportOptions) async throws
}
```

Suggested file layout:

```text
Hypnograph/
  Export/
    FCPXML/
      FCPXMLClipHistoryExporter.swift
      FCPXMLDocument.swift
      FCPXMLTime.swift
      PhotosAssetResolver.swift
```

### A4) FCPXML construction strategy

Time encoding:
- prefer rational times (avoid floating drift).
- central helper to emit `value/timescale s` attributes.

Resources:
- one project format.
- one asset entry per canonical source URL.
- deterministic resource IDs.

Spine/sequence:
- append sequential offsets through selected range.
- encode montage overlays as connected/lane clips.

### A5) Media URL resolution policy

`MediaSource.url(URL)`:
- use file URL directly.

`MediaSource.external(identifier)` (Photos):
- resolve official file URL through PhotoKit when available.
- strict v1 policy: if not resolvable in place, fail export with clear unresolved identifier list.

Official strategy notes:
- images: `PHContentEditingInput.fullSizeImageURL` often usable.
- videos: `requestAVAsset` may return `AVURLAsset` with file URL.
- strict in-place behavior should avoid implicit network/materialization.

Unpreferred fallback strategy (documented only):
- user-granted Photos Library bundle introspection/scanning.
- brittle across schema/platform changes; not recommended for v1.

### A6) Command integration notes

Suggested command placement pattern:
- close to history actions (`Clear Clip History`) for discoverability.

Dream-level entry point:

```swift
@MainActor
func exportClipHistoryFCPXML()
```

Responsibilities:
- load clip history.
- validate non-empty / valid range.
- show save panel for `.fcpxml`.
- invoke exporter with defaults.

### A7) Transitions planning (post-v1)

Default v1 is hard cuts.

If adding dissolve/fade later:
- overlap segment boundaries by transition duration.
- preserve total timing contract intentionally (shrink vs extend policy).
- validate target NLE import behavior per transition encoding.

### A8) Validation plan

1. Export synthetic history with 2-3 clips and montage layers.
2. Import into Final Cut Pro (primary baseline).
3. Import into DaVinci Resolve (compatibility check).
4. Verify:
   - order
   - duration
   - media relink correctness
   - layer stack behavior
   - blend mode survivability

### A9) Outstanding technical decisions

1. Duration authority: `targetDuration` vs play-rate-adjusted behavior.
2. Transform export: exact, approximate, or deferred.
3. Layer fill policy when segment vs selected-duration mismatch occurs.
4. Strict-only Photos policy vs optional materialized-copy fallback.
5. Whether Resolve blend fidelity is required for v1 or best-effort.
