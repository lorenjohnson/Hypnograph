---
last_reviewed: 2026-01-03T21:17:01Z
---

# Settings Architecture

## Scope
This document describes settings storage, defaults, and related persistent state.

## Sources
- `Hypnograph/Settings.swift`
- `Hypnograph/Environment.swift`
- `Hypnograph/HypnographState.swift`
- `Hypnograph/PlayerConfiguration.swift`
- `Hypnograph/MediaSources/ExclusionStore.swift`
- `Hypnograph/MediaSources/DeleteStore.swift`
- `Hypnograph/MediaSources/FavoriteStore.swift`

## Settings File

### Location
- `Environment.defaultSettingsURL` ->
  `~/Library/Application Support/Hypnograph/hypnograph-settings.json`.
- `Environment.ensureDefaultSettingsFileExists()` copies the bundled
  `default-settings.json` if no file exists.

### Settings Schema (Settings.swift)
- Output and snapshots:
  - `outputFolder`
  - `snapshotsFolder`
- Source libraries and filters:
  - `sources` (polymorphic array or dictionary)
  - `activeLibraries`
  - `sourceMediaTypes` (images/videos)
- Rendering defaults:
  - `outputResolution`
  - `playerConfig` (legacy: `montagePlayerConfig` / `sequencePlayerConfig`)
- UI state:
  - `effectsListCollapsed`
- Watch mode:
  - `watch`
- Audio routing:
  - `previewAudioDeviceUID`, `previewVolume`
  - `liveAudioDeviceUID`, `liveVolume`
- Legacy keys are supported for backward compatibility.

### Derived Values
- `outputURL`, `snapshotsURL`, `sourceLibraries`, `sourceLibraryOrder`.

## Settings Lifecycle
- `HypnographState` loads settings on init and calls `saveSettingsToDisk()` when
  settings change.
- Settings writes are JSON-encoded with stable ordering for diff readability.
- Settings are loaded on init and saved via `saveSettingsToDisk()` when modified.

## Related Persistent State

### Window State
- Stored separately at `~/Library/Application Support/Hypnograph/window-state.json`.
- Encoded via `WindowState` and saved by `HypnographState.saveWindowStateToDisk()`.

### Custom Photos Selection
- Stored in `custom-photos-selection.json` under Application Support.
- Managed by `HypnographState.setCustomPhotosAssets()`.

### Exclusions, Favorites, Deletions
- `exclusions.json` via `ExclusionStore`.
- `deletions.json` via `DeleteStore`.

### Effects Libraries
- Stored in `~/Library/Application Support/Hypnograph/effect-libraries/` and
  managed by `EffectsSession` (see effects architecture document).

## Environment Paths
- `Environment.appSupportDirectory` is the base path for app state.
- Additional directories:
  - `Environment.lutsDirectory`
  - `Environment.toolsDirectory`
  - `Environment.userServicesDirectory`
