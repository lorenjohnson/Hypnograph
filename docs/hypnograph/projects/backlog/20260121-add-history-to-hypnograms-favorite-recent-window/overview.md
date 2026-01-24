---
created: 2026-01-21
updated: 2026-01-21
status: Proposed (planning notes)
---

# Hypnograms Panel: History + Saved + Favorites

Goal: a single “Hypnograms” panel with three tabs (in this order):

1. **History** (clip history; unsaved-by-default)
2. **Saved** (saved hypnograms; “Recent” renamed to “Saved”)
3. **Favorites** (favorited saved hypnograms)

All three tabs should share the same row format (thumbnail + name/metadata + actions), with placeholders when a thumbnail is unavailable.

## Current state (today)

- **Saved/Favorites** are driven by `HypnogramStore`:
  - Persisted as `hypnogram-store.json`.
  - List UI is `Hypnograph/Views/Components/HypnogramListView.swift`.
- **History** is persisted separately as `clip-history.json`:
  - `Hypnograph/ClipHistoryFile.swift` stores `clips: [HypnogramClip]` and `currentClipIndex`.
  - `HypnogramClip` does not contain an embedded snapshot/thumbnail field.
- `.hypno`/`.hypnogram` saved files are `HypnogramRecipe` JSON with an embedded base64 JPEG `snapshot` (via `RecipeStore`).
- Finder previews rely on **Quick Look** (not “whatever is inside the JSON”):
  - Existing Quick Look preview controller reads `snapshot` and displays it:
    `HypnogramQuickLook/PreviewViewController.swift`.

## Proposed behavior

### Tabs and meaning

- **History**: show the live clip history (whatever is currently persisted in `clip-history.json`), not saved files.
- **Saved**: show `HypnogramStore` entries (newest first). “Recent” becomes “Saved”.
- **Favorites**: show `HypnogramStore` entries marked favorite, ordered newest-to-oldest by the time they were favorited (fallback to created date).

### Thumbnails

- History needs thumbnails to match the Saved/Favorites list UX.
- If a history item has no thumbnail yet, show the same placeholder used elsewhere.

## Data model options (History thumbnails)

Preferred: extend the existing clip-history persistence format rather than switching history entries to full recipes.

Option A (minimal): add a separate thumbnail map keyed by clip id
- Extend `ClipHistoryFile` with something like:
  - `thumbnailsByClipID: [UUID: String]` (base64 JPEG thumbnail)
- Benefits:
  - Keeps `HypnogramClip` untouched.
  - Backwards-compatible decode (missing map is fine).
  - Easy to prune alongside `historyLimit`.

Option B (richer): wrap each clip into a history entry
- Replace `clips: [HypnogramClip]` with `entries: [HistoryEntry]` where:
  - `HistoryEntry.clip: HypnogramClip`
  - `HistoryEntry.thumbnailBase64: String?`
- Benefits:
  - Keeps thumbnail colocated with the clip item.
- Costs:
  - Requires a migration path for old `clip-history.json`.

## Thumbnail generation (when/how)

The thumbnail should be captured once per history item, at the first convenient moment when the composited frame exists:

- Trigger candidates:
  - When a new clip is generated and first becomes active.
  - When the user navigates to a clip (if no thumbnail exists yet).
- Source of image:
  - Use the composited frame already available in preview (`EffectManager.currentFrame`) and encode a *small* thumbnail (e.g. 120–240px max dimension).
- Execution:
  - Do encode + file write on a background task to avoid hitching.
  - If no frame is available yet, leave it nil and retry once shortly later.
- Pruning:
  - When history is sanitized down to `historyLimit`, drop thumbnails for removed clips.

## Finder icon preview / Quick Look

Adding a `thumbnail` field to `HypnogramRecipe` (in addition to the existing `snapshot`) can help performance and UX, but it won’t change Finder icons by itself.

To make Finder show the thumbnail as the icon/preview:

- Add a **Quick Look thumbnail provider** (`QLThumbnailProvider`) in `HypnogramQuickLook` that:
  - Reads `thumbnail` first (fast), otherwise falls back to downsampling `snapshot`.
  - Returns that as the thumbnail image used by Finder (e.g. icon preview / gallery view).

Notes:
- The existing `QLPreviewingController` already uses `snapshot` for interactive preview.
- A thumbnail provider is the right place to surface a smaller embedded image for Finder.

## Non-goals (for v1 of this panel)

- Don’t change “History” persistence to full recipes unless we have a clear reason.
- Don’t embed 1080p snapshots in `clip-history.json` unless we explicitly accept large JSON writes and churn.
- Don’t require thumbnails for correctness; placeholders are acceptable.

## Open questions

- What minimal metadata should History rows show (timestamp, source count, duration, effects count)?
- Should History rows include “Save” / “Favorite” inline actions, or stay click-to-load only?
- Should History dedupe identical clips (likely no for v1; preserve chronological log)?
