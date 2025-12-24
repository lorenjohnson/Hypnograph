# Effects Architecture

## Overview

The effects system has **three tiers** that manage effect definitions:

1. **Library** (persistent) - Stable templates saved to disk, only modified explicitly
2. **Session State** (in-memory) - Working copy for the current app session, accumulates tweaks
3. **Recipe** (per-hypnogram) - The actual effects applied to a specific hypnogram

All three tiers use the same data type (`EffectDefinition`) and should support
the same operations through a unified API.

This document describes the current implementation, identifies issues, and
defines the target architecture.

---

## Data Structures

### The Library (`EffectConfigLoader` + `EffectsEditorViewModel`)

**Purpose:** Provides the list of available effects that users can choose from.

**Storage Location:**
- Primary: `~/Library/Application Support/Hypnograph/effects.json`
- Fallback: `effects-default.json` bundled in app
- Last resort: Hardcoded defaults in `EffectConfigLoader.hardcodedDefaults`

**Key Types:**
- `EffectConfig` - Root container with version and effects array
- `EffectDefinition` - JSON-serializable effect with name, type, params, hooks
- `EffectsEditorViewModel.effectDefinitions` - In-memory copy for UI

**Operations:**
- `EffectConfigLoader.loadEffects()` - Load library on startup
- `EffectConfigLoader.createNewEffect()` - Add new effect to library
- `EffectConfigLoader.updateParameter()` - Modify library effect
- `EffectsEditorViewModel.syncFromConfig()` - Sync UI from library

### The Recipe (`HypnogramRecipe`)

**Purpose:** Stores the actual effect configuration for a specific Hypnogram.

**Storage Location:** In-memory on `HypnographState.recipe`

**Key Fields:**
- `recipe.effects: [RenderHook]` - Instantiated effect chain (global)
- `recipe.effectDefinition: EffectDefinition?` - Editable definition (global)
- `recipe.sources[n].effects: [RenderHook]` - Instantiated per-source effects
- `recipe.sources[n].effectDefinition: EffectDefinition?` - Per-source definition

**Operations:**
- `RenderHookManager.setEffect(from: EffectDefinition)` - Set effect from definition
- `RenderHookManager.updateEffectParameter()` - Modify recipe effect params
- `RenderHookManager.addHookToChain()` - Add hook to recipe chain
- `RenderHookManager.removeHookFromChain()` - Remove hook from recipe

---

## Data Flow

### Effect Selection (Choosing an effect from the list)

```
User clicks effect in list
    │
    ▼
EffectsEditorView calls:
    state.activeRenderHooks.setEffect(from: definition, for: layer)
    │
    ▼
RenderHookManager.setEffect(from:for:):
    1. Stores definition → recipe.effectDefinition (via setter closure)
    2. Instantiates hook → recipe.effects (via effectsSetter closure)
    │
    ▼
UI reads from recipe via selectedDefinition
```

### Parameter Editing (Adjusting a slider)

```
User drags slider
    │
    ▼
Two paths (PROBLEMATIC - see Issues):

Path 1: Library update (for persistence)
    EffectsEditorViewModel.updateParameter()
        → EffectConfigLoader.updateParameter()
        → Saves to effects.json

Path 2: Recipe update (for UI/rendering)
    state.activeRenderHooks.updateEffectParameter()
        → Updates recipe.effectDefinition
        → Re-instantiates to recipe.effects
```

### Hook Chain Modification (Add/Remove/Reorder hooks)

```
User adds hook to chain
    │
    ▼
EffectsEditorView calls BOTH:
    1. viewModel.addHookToChain() → Updates library
    2. state.activeRenderHooks.addHookToChain() → Updates recipe
```

---

## Current Issues & Confusion

### Issue 1: Dual Source of Truth
The library and recipe both store effect definitions. This creates ambiguity:
- When you edit params, should it update both? Just recipe? Just library?
- Currently: Both are updated, which means editing Effect A in Hypnogram X also
  changes Effect A for all future Hypnograms

### Issue 2: Library as Template vs. Instance Store
**Unclear design question:** Is the library:
- (A) A **template** catalog - effects are copied to recipes, edits are local
- (B) A **live** catalog - recipes reference library effects, edits propagate

**Current behavior:** Hybrid (B-ish). Edits go to both, but the recipe stores
its own definition copy. This is confusing.

### Issue 3: "None" Selection State
Effect selection uses name matching between recipe and library. When the library
changes (rename, reorder), the matching can break, causing unexpected selections.

### Issue 4: Parameter Debouncing
The library saves with a 300ms debounce, but recipe updates are immediate.
This can cause brief inconsistencies.

---

## Target Architecture: Three-Tier Model

The solution is to recognize **three distinct tiers**, each with a clear purpose:

```
┌─────────────────────────────────────────────────────────────────────┐
│  LIBRARY (persistent)                                               │
│  ~/Library/Application Support/Hypnograph/effects.json              │
│                                                                     │
│  • Stable templates that survive app restart                        │
│  • Only modified by explicit "Save to Library" action               │
│  • Provides initial values when app launches                        │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ App Launch: load
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  SESSION STATE (in-memory, app lifetime)                            │
│  EffectsEditorViewModel.effectDefinitions (or dedicated type)       │
│                                                                     │
│  • Working copy of all effects for this session                     │
│  • Accumulates tweaks during performance                            │
│  • Persists across hypnogram changes within session                 │
│  • Lost on app quit (unless explicitly saved to Library)            │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ Effect Selection: copy
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  RECIPE (per-hypnogram)                                             │
│  HypnogramRecipe.effectDefinition / sources[n].effectDefinition     │
│                                                                     │
│  • What this specific hypnogram is using right now                  │
│  • Saved with hypnogram when exported/persisted                     │
│  • Only contains applied effects (not the full catalog)             │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow (Target)

### App Launch
```
Library (effects.json)
    │
    │ load
    ▼
Session State (in-memory)
    • All effects available for selection
    • Matches library initially
```

### Effect Selection
```
User selects "Datamosh" from list
    │
    ▼
Session State["Datamosh"]
    │
    │ deep copy
    ▼
Recipe.effectDefinition = copy of session's Datamosh
Recipe.effects = instantiated hooks from definition
```

### Parameter Editing
```
User adjusts slider
    │
    ├──► Session State: update definition (for future hypnograms)
    │
    └──► Recipe: update definition + re-instantiate (for current hypnogram)

Library: NOT touched
```

### New Hypnogram
```
newRandomHypnogram()
    │
    ▼
New Recipe created (no effect initially, or default)
    │
User selects "Datamosh"
    │
    ▼
Gets SESSION version (with accumulated tweaks)
    • NOT library version
```

### Save to Library (Explicit User Action)
```
User clicks "Save to Library" for current effect
    │
    ▼
Session State[effectName]
    │
    │ write
    ▼
Library (effects.json)
    • Now persists across app restarts
```

### App Quit
```
Session State → discarded (unless saved)
Library → unchanged (stable)
```

---

## Shared API Shape

All three tiers use `EffectDefinition` as the core data type:

```swift
// The same type at all levels
struct EffectDefinition: Codable {
    let name: String?
    let type: String?
    let params: [String: AnyCodableValue]?
    let hooks: [EffectDefinition]?  // For chains
}
```

### Operations (unified interface)

Each tier should support the same operations via a shared protocol or consistent API:

```swift
protocol EffectDefinitionStore {
    /// Get all available effect definitions
    var definitions: [EffectDefinition] { get }

    /// Get definition by index
    func definition(at index: Int) -> EffectDefinition?

    /// Update a parameter value
    mutating func updateParameter(
        effectIndex: Int,
        hookIndex: Int?,
        paramName: String,
        value: AnyCodableValue
    )

    /// Add hook to chain
    mutating func addHook(effectIndex: Int, hookType: String)

    /// Remove hook from chain
    mutating func removeHook(effectIndex: Int, hookIndex: Int)

    /// Reorder hooks
    mutating func reorderHooks(effectIndex: Int, from: Int, to: Int)

    /// Update effect name
    mutating func updateName(effectIndex: Int, name: String)
}
```

### Implementation per tier

| Tier | Implementation | Persistence |
|------|----------------|-------------|
| **Library** | `EffectConfigLoader` | `effects.json` on explicit save |
| **Session** | `EffectsEditorViewModel` (or new `SessionEffectStore`) | None (in-memory) |
| **Recipe** | `RenderHookManager` closures → `HypnogramRecipe` | With hypnogram export |

---

## Current Code Paths vs Target

| Action | Current | Target |
|--------|---------|--------|
| Select effect | Recipe ← Library | Recipe ← **Session** |
| Edit parameter | Library ✓, Recipe ✓ | Session ✓, Recipe ✓, Library ✗ |
| Add hook | Library ✓, Recipe ✓ | Session ✓, Recipe ✓, Library ✗ |
| Remove hook | Library ✓, Recipe ✓ | Session ✓, Recipe ✓, Library ✗ |
| Reorder hooks | Library ✓, Recipe ✓ | Session ✓, Recipe ✓, Library ✗ |
| Rename effect | Library ✓, Recipe ✓ | Session ✓, Recipe ✓, Library ✗ |
| Create new effect | Library ✓ | Session ✓, Library ✗ |
| Save to Library | (implicit) | **Explicit user action** |
| App launch | Library → Session → UI | Library → Session (no change) |

---

## Implementation Steps

### Phase 1: Stop Auto-Saving to Library
- Remove `saveToFile()` calls from `EffectConfigLoader.updateParameter()` etc.
- `EffectConfigLoader` becomes read-only after initial load
- Session state (`viewModel.effectDefinitions`) accumulates changes

### Phase 2: Selection Sources from Session
- `setEffect(from:)` should copy from session, not library
- Currently: `Effect.all[index]` comes from library via `EffectConfigLoader`
- Target: Selection UI reads from `viewModel.effectDefinitions`

### Phase 3: Add Explicit Save UI
- "Save to Library" button/menu for individual effects
- Optional: "Save All to Library" for batch save
- Confirmation dialog for overwrite

### Phase 4: Unify API (Optional Refactor)
- Extract `EffectDefinitionStore` protocol
- Implement for Library, Session, and Recipe
- Reduce code duplication in update logic

---

## UI Considerations (Deferred)

These decisions are deferred until the data architecture is solid:

- Where does "Save to Library" appear? (Per-effect button? Menu item?)
- Should there be visual indication of "modified from library"?
- How to handle "Revert to Library" for an effect?
- What happens if library effect is deleted but session/recipe still uses it?
- Should "Create New Effect" immediately save to library or stay in session?

