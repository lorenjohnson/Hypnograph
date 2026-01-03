---
last_reviewed: 2026-01-03T21:17:01Z
---

# Media Library Architecture

## Scope
This document covers how media sources are indexed, filtered, and loaded from
folders and Apple Photos.

## Sources
- `Hypnograph/MediaSources/MediaSourcesLibrary.swift`
- `Hypnograph/MediaSources/SourceLoader.swift`
- `Hypnograph/MediaSources/ApplePhotos.swift`
- `Hypnograph/MediaSources/StillImageCache.swift`
- `Hypnograph/MediaSources/ExclusionStore.swift`
- `Hypnograph/MediaSources/DeleteStore.swift`
- `Hypnograph/MediaSources/FavoriteStore.swift`
- `Hypnograph/HypnogramSource.swift`
- `Hypnograph/HypnographState.swift`

## Core Data Types

### MediaFile
- Abstracts over file URLs and Photos asset identifiers.
- `MediaFile.Source` is either `.url(URL)` or `.photos(localIdentifier)`.
- Provides async loading helpers (`loadAsset`, `loadImage`, `loadCGImage`).

### VideoClip
- A clip is a `MediaFile` plus `startTime` and `duration`.

### HypnogramSource
- A recipe source: clip + transforms + blend mode + effect chain.

## MediaSourcesLibrary

### Indexing Model
- Builds a lightweight `sourceIndex` of `(source, mediaKind)` entries.
- Avoids eager AVAsset or metadata loading for faster startup.
- Supports filtering by `SourceMediaType` (images, videos).

### Source Inputs
- Folder paths or single files.
- Apple Photos albums or the full Photos library.
- Custom Photos selection (explicit asset identifiers).
- If no explicit sources are provided, falls back to scanning the Photos
  originals directory on disk.

### Random Clip Selection
- `randomClip(clipLength:)` samples from `sourceIndex` and validates on demand.
- Failed sources are tracked in-memory to avoid repeated attempts.
- Video sources get randomized clip start times within duration.
- Image sources create a short-duration `VideoClip` with `startTime = .zero`.

### Exclusions and Deletions
- `applyExclusions()` filters out items in `ExclusionStore` and `DeleteStore`.
- Photos hidden assets are filtered via `ApplePhotos.cachedHiddenUUIDs`.

## SourceLoader
- Loads `HypnogramSource` into `LoadedSource` for the renderer.
- Caches `LoadedSource` by file ID to avoid repeated AVAsset loads.
- Supports:
  - AVURLAsset for file URLs.
  - `ApplePhotos.requestAVAsset` for Photos video assets.
  - `ApplePhotos.requestCIImage` for Photos image assets.
- Converts metadata transforms to CIImage space via `ImageUtils`.

## ApplePhotos
- Handles authorization and fetches PHAssets.
- Supports:
  - Loading AVAsset for videos.
  - Loading CIImage for still images.
  - Hidden asset caching for exclusion.
  - Album discovery for menu display.
  - Saving renders back to a "Hypnograms" album.

## StillImageCache
- Caches decoded still images to avoid repeated IO and decode errors.
- Always decodes via `CGImageSource` to prevent CIImage IOSurface issues.
- Cache is unbounded and must be cleared explicitly if needed.

## Persistence
- Exclusions: `Environment.exclusionsURL`.
- Deletions: `Environment.deletionsURL`.
- Favorites: `Environment.favoritesURL`.

## HypnographState Integration
- Tracks per-module library selections (`activeLibraryKeys`).
- Builds a combined library from folder paths, Photos albums, and custom
  Photos selection.
- Stores custom Photos identifiers in `custom-photos-selection.json`.
- Exposes `availableLibraries` with asset counts for UI menus.
