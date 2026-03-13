---
last_reviewed: 2026-03-13T00:00:00Z
---

# Media Library Integration

## Scope
This document covers how Hypnograph integrates app state and app persistence with shared media-library behavior in `HypnoCore`.

Shared media-library architecture now lives in HypnoPackages:
- [HypnoPackages media-library architecture](../../../HypnoPackages/docs/architecture/media-library.md)

## Sources

- `Hypnograph/App/HypnographState.swift`
- `Hypnograph/App/Main/Persistence/MainSettings.swift`
- `Hypnograph/App/Common/Support/Environment.swift`
- `HypnoCore/HypnoCoreConfig.swift`

## HypnographState Integration

- Tracks per-module library selections (`activeLibraryKeys`).
- Builds a combined media library from:
  - folder/file/glob sources
  - Photos album sources
  - custom Photos selection
- Stores custom Photos identifiers in `custom-photos-selection.json`.
- Exposes `availableLibraries` with computed asset counts for UI menus.
- Folder-based menu items are shown only when computed asset count is greater than zero.

## App Persistence Surfaces

### Main Settings

- Path: `~/Library/Application Support/Hypnograph/main-settings.json`
- Stores source-related settings including:
  - `sources`
  - `activeLibraries`
  - `sourceMediaTypes`

### Custom Photos Selection

- Path: `~/Library/Application Support/Hypnograph/custom-photos-selection.json`
- Managed by `HypnographState.setCustomPhotosAssets()`.

### Exclusions

- Persisted via `HypnoCoreConfig.exclusionsURL`.
- Applied by core media-library logic at indexing/filtering time.

## Notes

- Path/glob semantics and indexing behavior are defined in `HypnoCore` and documented in the shared architecture doc.
- This integration doc should stay app-focused: state composition, settings/persistence wiring, and UI-facing library selection behavior.
