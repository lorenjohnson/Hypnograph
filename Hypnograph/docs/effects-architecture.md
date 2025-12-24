# Effects Architecture

## Overview

The effects system has **two parallel data structures** that manage effects:

1. **The Library** - A shared catalog of effect templates available to all Hypnograms
2. **The Recipe** - Per-Hypnogram effect instances with their current parameter values

This document describes the current implementation, its data flows, and known issues.

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

## Recommendations

### Option A: Library as Template Catalog (Cleaner separation)

**Philosophy:** The library is a catalog of templates. When you select an effect,
a COPY of its definition goes into the recipe. Edits only affect the recipe.

**Changes needed:**
- Remove dual-update pattern - only update recipe during editing
- Add explicit "Save to Library" action for users who want to persist changes
- Library becomes read-only during effect use, only editable in a separate UI

**Pros:** Clear separation, per-hypnogram customization, no unexpected propagation
**Cons:** More work to share tweaked effects between hypnograms

### Option B: Library as Live Reference (Single source of truth)

**Philosophy:** The recipe only stores which library effect to use (by ID/index).
All parameters live in the library.

**Changes needed:**
- Remove `effectDefinition` from recipe, keep only reference
- All edits go to library
- All hypnograms using same effect share parameter values

**Pros:** Simpler model, changes automatically apply everywhere
**Cons:** No per-hypnogram customization

### Option C: Hybrid with Clear Rules (Current direction, refined)

**Philosophy:** Library provides defaults, recipe stores overrides.

**Changes needed:**
- Recipe stores delta from library defaults, not full copy
- UI clearly indicates "default" vs "customized" parameters
- "Reset to library defaults" action

---

## Current Code Paths (Reference)

| Action | Library Update | Recipe Update |
|--------|---------------|---------------|
| Select effect | No | Yes (copies def) |
| Edit parameter | Yes | Yes |
| Add hook | Yes | Yes |
| Remove hook | Yes | Yes |
| Reorder hooks | Yes | Yes |
| Rename effect | Yes | Yes |
| Create new effect | Yes | No (must select) |
| Delete effect | Yes | No (recipe keeps it) |

---

## Next Steps

1. Decide on Option A, B, or C above
2. Implement consistently across all operations
3. Consider persistence of recipe definitions (currently not saved to disk)
4. Add UI indicators for effect source (library default vs customized)

