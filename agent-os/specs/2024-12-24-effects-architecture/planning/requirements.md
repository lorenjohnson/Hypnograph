# Effects Naming Refactor

## Decision

**Drop "Hook" terminology entirely. Use "Effect" throughout.**

The codebase should match the UI/UX language. Users think in terms of "effects"
and "effect chains" (or "presets"), not "hooks."

---

## Target Terminology

| Concept | Type Name | Definition Type | UI Label |
|---------|-----------|-----------------|----------|
| Single effect | `Effect` (protocol) | `EffectDefinition` | "Effect" |
| Specific effects | `BlackAndWhiteEffect`, `DatamoshEffect`, etc. | — | "Black & White", etc. |
| Chain of effects | `EffectChain` | `EffectChainDefinition` | "Effect Chain" (or "Preset") |
| Library of chains | `EffectChainLibrary` | — | "Effect Chains" / "Presets" |

---

## Current → Target Mapping

### Protocol & Base Types

| Current | Target | File |
|---------|--------|------|
| `RenderHook` (protocol) | `Effect` | RenderHooks.swift |
| `ChainedHook` | `EffectChain` | ChainedHook.swift → EffectChain.swift |
| `NamedHook` | `NamedEffect` | RenderHooks.swift |
| `enum Effect` | `enum EffectChainLibrary` | RenderHooks.swift |
| `Effect.all` | `EffectChainLibrary.all` | RenderHooks.swift |

### Effect Implementations

| Current | Target |
|---------|--------|
| `BasicHook` | `BasicEffect` |
| `BlackAndWhiteHook` | `BlackAndWhiteEffect` |
| `ColorEchoHook` | `ColorEchoEffect` |
| `DatamoshMetalHook` | `DatamoshEffect` |
| `FeedbackLoopHook` | `FeedbackLoopEffect` |
| `FrameDifferenceHook` | `FrameDifferenceEffect` |
| `GhostBlurHook` | `GhostBlurEffect` |
| `HoldFrameHook` | `HoldFrameEffect` |
| `HueWobbleHook` | `HueWobbleEffect` |
| `LUTHook` | `LUTEffect` |
| `MirrorKaleidoHook` | `MirrorKaleidoEffect` |
| `PixelateMetalHook` | `PixelateEffect` |
| `RGBSplitSimpleHook` | `RGBSplitEffect` |

### Definition Types

| Current | Target | Notes |
|---------|--------|-------|
| `EffectDefinition` | `EffectChainDefinition` | Top-level chain definition |
| (embedded in above) | `EffectDefinition` | Individual effect within chain |
| `EffectConfig` | `EffectChainLibraryConfig` | Root of JSON file |

### Manager & Loader

| Current | Target |
|---------|--------|
| `RenderHookManager` | `EffectManager` |
| `EffectConfigLoader` | `EffectChainLoader` |
| `EffectRegistry` | `EffectRegistry` (keep) |

### Instance Variables & Methods

| Current | Target |
|---------|--------|
| `renderHooks` | `effectManager` |
| `activeRenderHooks` | `activeEffects` |
| `globalEffectDefinition` | `globalEffectChain` |
| `sourceEffectDefinition` | `sourceEffectChain` |
| `setEffect(from:)` | `setEffectChain(from:)` |
| `effectsSetter` | `effectChainSetter` |
| `hooks: [RenderHook]` | `effects: [Effect]` |

---

## JSON Schema Change

### Current (ambiguous)

```json
{
  "version": 1,
  "effects": [
    { "name": "B&W", "type": "BlackAndWhiteHook", "params": {...} },
    { "name": "Datamosh", "hooks": [
        { "type": "DatamoshMetalHook", "params": {...} }
      ]
    }
  ]
}
```

### Target (always chain format)

```json
{
  "version": 2,
  "effectChains": [
    {
      "name": "B&W",
      "effects": [
        { "type": "BlackAndWhiteEffect", "params": {...} }
      ]
    },
    {
      "name": "Datamosh",
      "effects": [
        { "type": "DatamoshEffect", "params": {...} }
      ]
    }
  ]
}
```

Key changes:
- `effects` → `effectChains` (top level)
- `hooks` → `effects` (within chain)
- `*Hook` → `*Effect` (type names)
- Always use array format, even for single effect

---

## Files to Rename

| Current | Target |
|---------|--------|
| `Renderer/Effects/ChainedHook.swift` | `Renderer/Effects/EffectChain.swift` |
| `Renderer/Effects/BasicHook.swift` | `Renderer/Effects/BasicEffect.swift` |
| `Renderer/Effects/BlackAndWhiteHook.swift` | `Renderer/Effects/BlackAndWhiteEffect.swift` |
| ... (all *Hook.swift files) | ... (*Effect.swift) |

---

## Implementation Order

### Phase 1: Core Protocol (foundation)
1. Rename `RenderHook` protocol → `Effect`
2. Keep `RenderHook` as typealias temporarily for compilation
3. Update protocol requirements if needed

### Phase 2: Effect Implementations (bulk rename)
1. Rename all `*Hook` classes/structs → `*Effect`
2. Rename files to match
3. Update internal references

### Phase 3: Chain & Library
1. Rename `ChainedHook` → `EffectChain`
2. Rename `enum Effect` → `enum EffectChainLibrary`
3. Update `Effect.all` → `EffectChainLibrary.all`

### Phase 4: Definition Types
1. Current `EffectDefinition` → `EffectChainDefinition`
2. Create new `EffectDefinition` for individual effects within chains
3. Update `EffectConfig` → `EffectChainLibraryConfig`

### Phase 5: Manager & Loader
1. Rename `RenderHookManager` → `EffectManager`
2. Rename `EffectConfigLoader` → `EffectChainLoader`
3. Update all instance variable names

### Phase 6: JSON Migration
1. Update `effects-default.json` to new schema
2. Add migration code to read old format, write new format
3. Update type strings in JSON (`*Hook` → `*Effect`)

### Phase 7: Cleanup
1. Remove deprecated typealiases
2. Update all comments and documentation
3. Verify UI labels match new terminology

---

## Risk Mitigation

- **Compile after each phase** - catch breaks early
- **Keep typealiases temporarily** - allows gradual migration
- **JSON migration** - loader reads both formats during transition
- **Git commits per phase** - easy to bisect if issues arise

