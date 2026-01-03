---
last_reviewed: 2026-01-03T21:17:01Z
---

# Effects System Architecture

## Scope
This document describes the effect data model, effect library, runtime processing,
and how effects integrate into rendering.

## Sources
- `Hypnograph/Renderer/Effects/Effect.swift`
- `Hypnograph/Renderer/Effects/ParameterSpec.swift`
- `Hypnograph/EffectLibrary/EffectConfigSchema.swift`
- `Hypnograph/EffectLibrary/EffectConfigLoader.swift`
- `Hypnograph/EffectLibrary/EffectRegistry.swift`
- `Hypnograph/EffectLibrary/EffectsSession.swift`
- `Hypnograph/EffectLibrary/EffectManager.swift`
- `Hypnograph/Renderer/Core/FrameBuffer.swift`
- `Hypnograph/Renderer/Core/RenderContext.swift`

## Data Model

### EffectDefinition
- A single effect entry: `type` and `params` plus optional display `name`.
- `_enabled` param gates whether an effect runs.

### EffectChain
- A named sequence of `EffectDefinition` entries.
- Stored on `HypnogramRecipe` as the global chain and per-source chain.
- Caches instantiated `Effect` objects on demand, and resets cache when definitions change.
- Chain names are used to match selections when reapplying after library changes.

### EffectLibraryConfig
- JSON file format: `{ "version": Int, "effects": [EffectChain] }`.
- Used by `EffectsSession` and `EffectConfigLoader`.

### AnyCodableValue
- Type-erased parameter value that supports `int`, `double`, `bool`, and `string`.

## Effect Protocol
`Effect` is a pure transform over `(context, image) -> image`:
- `requiredLookback` declares temporal history needs.
- `parameterSpecs` defines parameter metadata and defaults.
- `apply(to:context:)` performs the transform.
- `reset()` clears internal state.
- `copy()` returns a fresh instance for export isolation.

## Parameter Metadata
- `ParameterSpec` encodes parameter type, range, and defaults.
- `EffectRegistry.defaults()` derives defaults directly from `parameterSpecs`.
- File parameters can populate options from `Environment.lutsDirectory` via a cached scan.

## Registry
`EffectRegistry` maps string type names (e.g. `DatamoshMetalEffect`) to effect
metatypes and provides:
- `create(type:params:)`
- `parameterSpecs(for:)`
- `defaults(for:)`

## Effect Library

### EffectsSession
- Owns the editable list of effect chains for a context (montage, sequence, live).
- Persists to JSON in `~/Library/Application Support/Hypnograph/effect-libraries/`.
- Uses debounced saves and tracks `isDirty` via a hash of the config.
- Exposes a thread-safe snapshot for non-main-actor consumers.

### EffectConfigLoader
- Loads `effects-default.json` with JSONC support (comment stripping).
- Fallback order: user file -> debug source file -> bundled defaults -> minimal defaults.

## Runtime Processing

### EffectManager
- Owns the `FrameBuffer` and global frame index.
- Reads and writes effect chains through closures wired to the recipe.
- Applies:
  - Per-source effects before blending.
  - Global effects after blending and normalization.
- Supports effect cycling and per-layer effect selection.
- Supports blend normalization and flash solo.
- Integrates with `FrameBufferPreloader` for temporal effects.

### RenderContext
- Passed into effects during rendering.
- Exposes current time, frame index, output size, and frame history.

## Isolation and Mode Separation
- Preview uses the active player's `EffectManager` and `EffectsSession`.
- Performance display uses its own `EffectManager` and `EffectsSession`.
- Export uses `EffectManager.forExport(recipe:)` and `recipe.copyForExport()` to
  avoid sharing mutable effect state.

## Persistence Locations
- Bundled defaults: `Hypnograph/EffectLibrary/effects-default.json` (in app bundle).
- Session files (per mode):
  - `montage-effects.json`
  - `sequence-effects.json`
  - `live-effects.json`

## Integration Points
- `EffectsEditorView` edits `EffectsSession` and uses `EffectManager` to apply
  changes to the active recipe.
- `FrameCompositor` reads the recipe and applies chains each frame.
