# Export Clip History (FCPXML): Implementation Plan

## Summary

Implement a new export routine that converts `ClipHistoryFile` (materialized clip history) into an FCPXML timeline referencing **original media** on disk. Add a Hypnograph menu item: **Export Clip History (FCPXML)** below **Clear Clip History**.

Key design goals:
- No rendering: reference original media assets (URLs).
- Montage export: represent `HypnogramClip.sources` as stacked layers with configurable overlap blend mode (default `"screen"`).
- Default transitions: none (hard cuts); document what’s required to add fade/dissolve as an option.

## Proposed API Surface (code-level)

### 1) Export options

Create a dedicated options struct in Hypnograph (app-level):

```swift
struct FCPXMLClipHistoryExportOptions {
    var timelineName: String = "Hypnograph Clip History"

    // Timeline format
    var frameRate: Int = 30
    var renderSize: CGSize = CGSize(width: 1920, height: 1080)

    // Montage behavior
    var montageBlendMode: String = "screen"
    var includeMontageLayers: Bool = true   // if false, export only the base layer

    // Clip timing behavior (decision required)
    enum ClipDurationPolicy { case targetDuration, targetDurationAdjustedForPlayRate }
    var clipDurationPolicy: ClipDurationPolicy = .targetDuration

    // Optional transitions (default none)
    enum InterClipTransition {
        case none
        case dissolve(durationSeconds: Double)
        case fadeToBlack(durationSeconds: Double)
    }
    var interClipTransition: InterClipTransition = .none

    // Photos resolution policy (decision required)
    enum PhotosResolutionPolicy {
        case requireFileURLInPlace  // fail if no stable file:// URL exists
        case allowMaterializedCopy(exportFolderURL: URL)
    }
    var photosResolutionPolicy: PhotosResolutionPolicy = .requireFileURLInPlace
}
```

Notes:
- `montageBlendMode` is a single setting applied to overlap layers (source indices ≥ 1) in v1.
- `interClipTransition` is intentionally scoped to a small set; custom Hypnograph transitions are out of scope.
- `photosResolutionPolicy` exists because “original file in place” is not always resolvable for all Photos assets.

### 2) Exporter entry point

Add a single exporter type:

```swift
final class FCPXMLClipHistoryExporter {
    func export(history: ClipHistoryFile, to url: URL, options: FCPXMLClipHistoryExportOptions) async throws
}
```

### 3) Where the code lives

Suggested structure:

```
Hypnograph/
  Export/
    FCPXML/
      FCPXMLClipHistoryExporter.swift
      FCPXMLDocument.swift          // minimal DOM structs OR string builder
      FCPXMLTime.swift              // rational time formatting helpers
      PhotosAssetResolver.swift      // resolves MediaSource.external to file URLs (app-level)
```

## FCPXML Construction Strategy

### Time formatting (avoid float seconds)

FCPXML prefers rational durations (e.g., `1001/30000s`), and floating seconds can accumulate rounding drift.

Plan:
- Use a single timeline timescale: `timebase = lcm(600, frameRate * 1000)` or similar.
- Provide `FCPXMLTime` helper:
  - `init(_ cmTime: CMTime, timescale: Int32)`
  - `var attributeValue: String` → `"\(value)/\(timescale)s"`

### Resources section

Create:
- One `<format>` for the project (size + frameDuration).
- One `<asset>` per unique referenced file URL.

Implementation notes:
- Key assets by canonical file URL string.
- Use deterministic IDs (`r1`, `r2`, etc.) to keep output stable.
- Store durations where available, but don’t require it to build the timeline.

### Sequence / spine section (no transitions)

Flatten history into sequential segments:
- `offset` starts at `0`
- each history clip appends length `duration = clipDuration(clip, policy)`

Montage mapping:
- Base layer (source 0) goes into `<spine>` as the main `asset-clip`.
- Additional layers go in as “connected clips” / lanes for the same time range.

### Clip timing + exact in/out mapping (important)

Each `HypnogramSource.clip` represents a *trimmed region* of the original asset. Export must preserve these trims exactly:
- Exported “in point” = `HypnogramSource.clip.startTime`
- Exported “trim length” = `HypnogramSource.clip.duration`

In FCPXML terms, each exported clip instance should set:
- `asset-clip start="…"` (source in point) from `startTime`
- `asset-clip duration="…"` (how long that instance plays) from `duration`

**If a history segment needs to be longer than a source’s selected duration**, the exporter must choose a fill policy (decision required), but it must *not* extend beyond the user-selected in/out in v1.

Proposed fill policy (v1, decision required):
```swift
enum LayerFillPolicy {
    /// Timeline segment length is allowed to shrink to the selected duration.
    case clampSegmentToSelectedDuration
    /// Repeat the selected range (emit multiple back-to-back clip instances).
    case loopSelectedRange
    /// Stop at the selected out-point and hold (still frame) to the segment end (not ideal for video).
    case holdLastFrame
    /// Stop at the selected out-point and leave a gap (black / transparent).
    case leaveGap
}
```

Notes:
- `loopSelectedRange` preserves the exact in/out *per loop* and tends to match Hypnograph’s “generative montage” feel.
- `clampSegmentToSelectedDuration` preserves trims and avoids looping artifacts, but changes the total exported timeline length compared to in-app playback if `targetDuration` differs.
- This interacts with `HypnogramClip.targetDuration` vs `VideoClip.duration`; decide which is authoritative for segment length in v1.

Transforms:
- `HypnogramSource.transforms` should be exported to equivalent FCPXML transform params where possible.
- v1 can start with only translation/scale/rotation if needed, or skip transforms entirely (decision required).

Blend mode:
- Apply `options.montageBlendMode` for layers ≥ 1.
- The exact encoding is the main spec risk:
  - FCPXML can encode compositing modes, but Resolve import fidelity varies.
  - Plan for a compatibility matrix (FCP vs Resolve).

## Media URL Resolution (original media)

### URL-based sources

`MediaSource.url(URL)` → use `file://` URL directly.

### Apple Photos sources (external identifiers)

`MediaSource.external(identifier: String)` → resolve to file URL.

Add app-level resolver (since it requires PhotoKit app entitlements/runtime access):

```swift
protocol ExternalMediaURLResolver {
    func resolveToFileURL(file: MediaFile) async throws -> URL
}
```

Implementation sketch:
- Image assets:
  - `PHAsset.requestContentEditingInput(...)` → `fullSizeImageURL`
- Video assets:
  - `PHImageManager.requestAVAsset(...)`
  - if result is `AVURLAsset` and `url.isFileURL`, use it

### Apple Photos: official vs bruteforce path resolution

**Preferred (official) strategy**: use PhotoKit to retrieve a stable file URL *only when it truly exists in place*.
- For images, `PHContentEditingInput.fullSizeImageURL` often points at:
  - an external “referenced” original (best case), or
  - a file inside the Photos Library bundle (still a valid `file://` URL).
- For videos, `requestAVAsset` sometimes yields an `AVURLAsset` with a `file://` URL when the original is locally present.

Important implementation detail:
- Set request options to avoid implicitly downloading/materializing:
  - `isNetworkAccessAllowed = false` (strict “in place” behavior)
  - Prefer highest quality delivery mode (`.highQualityFormat`) so we don’t get proxies.

**Fallback (unofficial / risky) strategy**: attempt to locate the original inside a user-selected Photos Library bundle.
- High-level idea:
  - User selects `Photos Library.photoslibrary` via open panel (security-scoped access).
  - Parse the asset UUID portion of `PHAsset.localIdentifier`.
  - Use internal library indexing (directory scan and/or SQLite database) to map UUID → original file path under `originals/` / `Masters/`.
- Risks:
  - Not a supported Apple API; schema and paths can change across macOS/Photos versions.
  - Very expensive to scan on large libraries.
  - iCloud-optimized assets may not exist locally as originals.
  - Sandboxed access may block direct reads unless the user explicitly grants access to the library bundle.

Recommendation for v1:
- Implement only the official strategy, and keep export **strict**:
  - If the Photos asset does not resolve to a stable in-place `file://` URL, fail export and list unresolved identifiers.
- Document the bruteforce strategy as a future option only if strict mode proves too limiting in practice.

Failure behavior:
- If `requireFileURLInPlace`: throw an error with a list of unresolved identifiers.
- If `allowMaterializedCopy`: export the underlying resource bytes to a folder and reference the copy.

## UI Integration

### Menu item placement

Add in `Hypnograph/AppCommands.swift` within the leftmost Hypnograph command group:
- Below:
  - `Button("Clear Clip History") { dream.clearClipHistory() }`
- Add:
  - `Button("Export Clip History (FCPXML)") { dream.exportClipHistoryFCPXML() }`

### Dream entry point

Add a `Dream` method:

```swift
@MainActor
func exportClipHistoryFCPXML()
```

Responsibilities:
- Load history from `Environment.clipHistoryURL` via `ClipHistoryIO.load(...)`.
- If empty, show a user-visible error.
- Present NSSavePanel:
  - default filename: `Hypnograph Clip History.fcpxml`
  - allowed type: `fcpxml`
- Gather export options:
  - v1: fixed defaults + `montageBlendMode = "screen"`
  - later: show a small sheet for options
- Call `FCPXMLClipHistoryExporter.export(...)` on a background task, with progress indicator (optional).

## Optional Transitions (Planning Only)

Default: none.

To support dissolve/fade between history clips, the exporter must:

1) Overlap adjacent clips by transition duration:
- If transition duration = `T`, then clip A ends at `end - T/2` and clip B starts at `start + T/2`, or similar.
- Insert a transition element that references a built-in effect (e.g., “Cross Dissolve”).

2) Ensure timeline durations remain consistent:
- Either shrink each clip slightly to accommodate overlaps
- Or extend the timeline (less desirable if “history timing” should remain stable)

3) Encode transition in FCPXML:
- This requires knowledge of the correct element structure and effect identifiers.
- Resolve import may differ from FCP.

Recommendation:
- Keep v1 at hard cuts.
- Add dissolve only if import fidelity is verified for the target NLE(s).

## Testing / Validation Plan

1) Create a small synthetic history file in dev:
- 2–3 history clips
- each with:
  - base file URL video
  - montage clip with 2 layers and Screen blend
  - at least one Photos-sourced asset if available

2) Export `.fcpxml` and import into:
- Final Cut Pro (primary correctness baseline)
- DaVinci Resolve (check what blend modes and transforms survive)

3) Verify:
- Timeline length matches expected history duration
- Clips are in correct order
- Media relinks correctly and points to original paths
- Montage layers appear stacked and blend mode is applied

## Open Questions (need decisions before implementation)

1) **Play rate policy**:
- Should timeline duration follow `clip.targetDuration` as-is, or be adjusted by `clip.playRate`?

2) **Transform export**:
- Export transforms exactly, approximate, or skip in v1?

3) **Segment duration + fill policy**:
- When `HypnogramClip.targetDuration` does not match a source’s selected duration, what’s the v1 behavior?
- Choose `LayerFillPolicy` and decide which duration is authoritative for the segment.

4) **Photos strictness (v1 requirement)**:
- v1 should be strict: if a Photos asset cannot resolve to a stable in-place `file://` URL, export fails.
- Question is only whether we want a future “materialize originals” fallback option.

5) **Blend mode fidelity target**:
- Is “works in Final Cut” sufficient, or must it also preserve Screen in Resolve?
