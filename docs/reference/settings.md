---
last_reviewed: 2026-03-12T00:00:00Z
---

# Settings Architecture

## Scope
This document describes current settings storage, defaults, and related persistent state for Hypnograph.

## Sources
- `Hypnograph/App/Common/Support/Environment.swift`
- `Hypnograph/App/HypnographState.swift`
- `Hypnograph/App/Main/Persistence/MainSettings.swift`
- `Hypnograph/App/Main/Persistence/MainSettingsStore.swift`
- `Hypnograph/App/AppSettings.swift`
- `Hypnograph/App/AppSettingsStore.swift`
- `Hypnograph/App/EffectsStudio/Persistence/EffectsStudioSettings.swift`
- `Hypnograph/App/EffectsStudio/Persistence/EffectsStudioSettingsStore.swift`
- `HypnoCore/Cache/PersistentStore.swift`
- `HypnoCore/HypnoCoreConfig.swift`

## Settings Files

### Main Settings
- Path: `~/Library/Application Support/Hypnograph/main-settings.json`
- Store: `MainSettingsStore`
- Contains primary playback/composition settings, including:
  - source libraries (`sources`, `activeLibraries`, `sourceMediaTypes`)
  - output/snapshot folders
  - resolution, framing, transition, history, and playback defaults

### App Settings
- Path: `~/Library/Application Support/Hypnograph/hypnograph-settings.json`
- Store: `AppSettingsStore`
- Contains app-global UI policy flags, currently:
  - `keyboardAccessibilityOverridesEnabled`
  - `effectsStudioEnabled`

### Effects Studio Settings
- Path: `~/Library/Application Support/Hypnograph/effects-studio-settings.json`
- Store: `EffectsStudioSettingsStore`
- Contains Effects Studio panel/UI state.

## Initialization and Lifecycle
- On app startup, `HypnographApp` calls `Environment.ensureDefaultSettingsFilesExist()`.
- Each store is a `PersistentStore<T>`:
  - loads from disk on init
  - exposes reactive `value`
  - persists updates with debounced saves
- App runtime reads/writes through stores:
  - `HypnographState.settingsStore` for main runtime settings
  - `HypnographState.appSettingsStore` for app-global settings

## Source Configuration Note
- Source paths/globs are read from `MainSettings.sources` in `main-settings.json`.
- `hypnograph-settings.json` does not contain source libraries.

## Related Persistent State

### Window State
- `~/Library/Application Support/Hypnograph/window-state.json`
- Managed by `HypnographState` (`WindowState`).

### Custom Photos Selection
- `~/Library/Application Support/Hypnograph/custom-photos-selection.json`
- Managed by `HypnographState.setCustomPhotosAssets()`.

### Exclusions and Effects Data
- `exclusions.json` via `ExclusionStore`
- effects libraries under `effect-libraries/`
- runtime effects under `runtime-effects/`

## Environment Paths
- `Environment.appSupportDirectory` is the base path for app state.
- Additional directories include:
  - `Environment.lutsDirectory`
  - `Environment.toolsDirectory`
  - `Environment.userServicesDirectory`
