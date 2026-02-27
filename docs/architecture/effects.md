---
last_reviewed: 2026-02-26T00:00:00Z
---

# Effects System Architecture

## Scope
This document describes the effect data model, effect library, runtime processing,
and how effects integrate into rendering.

## Sources

- `HypnoCore/Renderer/Effects/Core/Effect.swift`
- `HypnoCore/Renderer/Effects/Core/MetalEffect.swift`
- `HypnoCore/Renderer/Effects/Implementations/ParameterSpec.swift`
- `HypnoCore/Renderer/Effects/Library/EffectConfigSchema.swift`
- `HypnoCore/Renderer/Effects/Library/EffectConfigLoader.swift`
- `HypnoCore/Renderer/Effects/Library/EffectRegistry.swift`
- `HypnoCore/Renderer/Effects/Library/EffectsSession.swift`
- `HypnoCore/Renderer/Effects/Library/EffectManager.swift`
- `HypnoCore/Renderer/Core/FrameBuffer.swift`
- `HypnoCore/Renderer/Core/RenderContext.swift`

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

## MetalEffect Base Class

`MetalEffect` provides shared infrastructure for Metal compute shader effects:

- Handles device, command queue, and texture cache setup.
- Manages CVPixelBuffer pools for multi-pass effects.
- Provides helpers: `ensureBuffers()`, `texture(from:)`, `render(_:to:)`, `threadgroupConfig()`.
- Subclasses override `shaderFunctionName` and implement `apply(to:context:)`.
- Used by: BlockFreezeMetalEffect, GlitchBlocksMetalEffect, ColorEchoMetalEffect,
  PixelDriftMetalEffect, TimeShuffleMetalEffect, GaussianBlurMetalEffect, PixelateMetalEffect.

## Parameter Metadata
- `ParameterSpec` encodes parameter type, range, and defaults.
- `ParameterSpec.randomValue()` generates a random value within the spec's constraints.
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
- Owns the editable list of effect chains for a context (preview/live/export).
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
- Live display uses its own `EffectManager` and shares the global `EffectsSession`.
- Export uses `EffectManager.forExport(recipe:)` and `recipe.copyForExport()` to
  avoid sharing mutable effect state.

## Persistence Locations
- Bundled defaults: `HypnoCore/Renderer/Effects/Library/effects-default.json` (bundled with HypnoCore).
- Session file:
  - `effects-library.json`

## Integration Points
- `EffectsEditorView` edits `EffectsSession` and uses `EffectManager` to apply
  changes to the active recipe.
- The internal compositor reads the recipe and applies chains each frame.

## Runtime Effect Identity + Version Policy

Runtime effects are user-editable assets stored in Application Support under
`runtime-effects/<uuid>/effect.json` + `shader.metal`.

Rules:
- `uuid` is immutable identity for an effect.
- `name` is user-facing only (not identity).
- `version` uses semver and is used for same-UUID update checks.

Bundled seed/update behavior:
- First run: bundled runtime assets are copied into user space.
- Later runs: for an existing UUID, bundled asset replaces local only when
  bundled `version` is newer.
- If bundled `version` is equal or older, local copy is kept.

Change policy:
- Non-breaking fixes for an existing effect can use same UUID + version bump.
- Visual/behavioral look changes should ship as a new UUID (new effect), not an
  in-place replacement, so existing recipes keep their look.

Authoring guidance:
- User-edited variants should be treated as new effects (new UUID, new name),
  not modifications of canonical bundled UUIDs.
