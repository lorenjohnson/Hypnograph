---
doc-status: done
---

# Effects System Refactor

## Naming Conventions

Current naming (this project):
- **EffectChain** - A named collection of effects applied in sequence
- **EffectChainsLibrary** - A stored collection of chain templates (user library, bundled presets, imported files)
- **EffectChainsSession** - The unified container managing Current, Recent, and multiple Libraries

Future consideration (not this project):
- Effect Chains may be renamed to **Treatments**
- Classes would become `TreatmentsLibrary`, `TreatmentsSession`, etc.
- Each Treatment contains a chain of Effects

The naming is intentionally verbose to make future renames straightforward.

---

## Problem Statement

The current effects system has blurry boundaries between concepts:

1. **No "working copy" concept** - Editing an effect immediately saves to library AND updates the recipe
2. **Name-based matching** - Library↔Recipe matching by name breaks on rename
3. **Missing simple UX wins** - No duplicate chain, no history of recently used chains
4. **Overbuilt and underbuilt** - Complex persistence machinery but missing basic operations

## Goals

- Clear separation: Libraries are templates, recipes store full copies
- UUID-based identity with optional template linking (`sourceTemplateId`)
- Recent history for quick access to previously used chains
- Per-chain actions: Duplicate, Save to Library, Update Library Entry

---

## Architecture

### Core Model

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  EffectChainsSession                                                        │
│  ━━━━━━━━━━━━━━━━━━━━                                                      │
│  Unified container with three distinct sections:                            │
│                                                                             │
│  CURRENT                                                                    │
│  ━━━━━━━                                                                   │
│  • Shows chains applied to each target (Global, Source 1, Source 2, etc.)  │
│  • Each entry is a COPY stored in the recipe (own UUID)                    │
│  • Stores sourceTemplateId for "Update Library Entry" functionality        │
│  • Selection state = which target (Global/Source N) is being edited        │
│  • Rows reflect the active recipe: Global + current sources                │
│  • Rows are always shown for existing targets (even if "None")             │
│  • Source rows appear/disappear as sources are added/removed in the recipe │
│                                                                             │
│  RECENT                                                                     │
│  ━━━━━━                                                                    │
│  • History of previously applied chains (last 100, show last 10)           │
│  • When applying a new chain, the OLD chain (being replaced) goes to Recent│
│  • Cross-hypnogram, persists across restarts                               │
│  • Shared between Montage, Sequence, and Live modes                         │
│  • Exact-deduped by params hash (same effects + same params = same entry)  │
│  • Allows multiple "variants" of the same template (see Variant UX below)  │
│  • Re-applying a chain from Recent bumps it to top (updates timestamp)     │
│  • "Show more" link to reveal older entries                                │
│                                                                             │
│  LIBRARIES                                                                  │
│  ━━━━━━━━━                                                                 │
│  • Named collections of chain templates                                     │
│  • Bundled: ships with app (bundled)                                       │
│  • User libraries: editable, can have multiple                             │
│  • Per-library actions: Save, Revert, Hide, Delete                         │
│  • Collapsible sections                                                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data Model

**EffectChain properties:**
```swift
final class EffectChain {
    var id: UUID                    // Unique to this instance (template OR recipe instance)
    var sourceTemplateId: UUID?     // Optional link back to a library template (update target)
    var name: String?               // Optional custom name
    var effects: [EffectDefinition] // The actual effects
    var params: [String: AnyCodableValue]?

    var paramsHash: String {
        // Stable hash of effect types + all param values (sorted) for exact dedupe
    }

    // Note: runtime-instantiated effect cache is not part of the model,
    // is not serialized, and is never copied between instances.

    // Display name logic:
    // 1. If name is set → show name
    // 2. Else → show "Effect1 + Effect2 + ..." (auto-generated from effects list)
}
```

### Key Principles

1. **Libraries are templates** — selecting a chain creates a copy
2. **Recipe stores full chain data** — self-contained, not references
3. **Bundled is bundled** — selecting from Bundled applies directly; use "Copy to My Effects" to create an editable template
4. **Recent is auto-populated** — snapshots with exact-dedupe by params hash
5. **sourceTemplateId is optional** — only for "Update Library Entry" convenience

### Scope & Persistence

- **Current is per-mode**: Montage, Sequence, and Live each have their own current recipe, so the CURRENT section reflects the active mode.
- **Recent + Libraries are global**: RECENT and LIBRARIES are shared across modes and persist across app restarts.
- **Targets**: "Global + Source N" always refers to the active recipe's sources (layers).

### Selection Model

Selection state lives in Current, not in chain rows:

- User selects target (Global / Source N) in Current section
- Current section shows what's applied, with active target highlighted
- Clicking a chain in Recent or Libraries = apply it to the active target
- All chains outside Current are templates to pick from

### Data Flow

```
APPLYING A CHAIN FROM LIBRARY
─────────────────────────────
1. User has target selected (e.g., Global)
2. User clicks chain in a library
3. Create recipe instance copy (new UUID), set sourceTemplateId = template UUID
4. Apply copy to target (stored in recipe)
5. Add snapshot of any previously applied Effect Chain to Recent (if non-empty and not duplicate by params hash)

APPLYING A CHAIN FROM RECENT
────────────────────────────
1. User clicks chain in Recent
2. Add snapshot of any previously applied Effect Chain to Recent (if non-empty and not duplicate by params hash)
3. Create recipe instance copy (new UUID)
4. Preserve sourceTemplateId if present
5. Apply copy to target (stored in recipe)
6. Bump the selected Recent entry to top (update timestamp)

EDITING PARAMS IN CURRENT
─────────────────────────
1. User edits chain applied to Global
2. Changes saved to recipe (the copy in Current)
3. Library template unchanged
4. Recent entry unchanged (it's a snapshot)

"UPDATE LIBRARY ENTRY" (from Current or Recent)
───────────────────────────────────────────────
1. Only available if sourceTemplateId exists, template still exists, and the template is writable
2. Overwrites library template with current params
3. Library marked dirty (if auto-save off)

"COPY TO MY EFFECTS" (from Current or Recent)
─────────────────────────────────────────────
1. Available if the current chain is not linked to a writable template
2. Creates a new template entry in "My Effect Chains" (same name by default)
3. Sets sourceTemplateId on the current chain to the new template UUID

"SAVE TO LIBRARY..." (from Current or Recent)
─────────────────────────────────────────────
1. Always available
2. Opens picker: which library? what name?
3. Creates new template entry (or replaces if same name, with confirmation)
4. Sets sourceTemplateId on the current chain to new template

STARTING FROM "NONE" (empty chain)
─────────────────────────────────
1. Every target (Global/Source N) always has an EffectChain in the recipe; it may be empty ("None")
2. User selects a target row that shows "None"
3. In the right panel, user adds effects to the chain and begins tuning params
4. If the user applies a template afterward, the prior (non-empty) chain is pushed to Recent
```

---

## Implementation Plan

### MVR (Minimum Viable Refactor) - Steps 1–4 (Complete)

Goal: deliver the "working copy" and shared UX structure while keeping the app functional throughout.

1. **Identity + hashing** ✅
   - Add `id`, `sourceTemplateId`, and `paramsHash` to `EffectChain`
   - Introduce `clone()` and `init(duplicating:sourceTemplateId:)`

2. **Working copy editing + List UI** ✅
   - CURRENT edits recipe chains (no template leakage)
   - Left panel becomes a sectioned SwiftUI `List` (CURRENT / RECENT / LIBRARIES; RECENT can be empty initially)

3. **Recent history** ✅
   - Persist `effects-recent.json`, capture "replaced/cleared" chains
   - Show `Variant · <hashSuffix>` for variants (hash-only)

4. **Global libraries** ✅
   - Use a single shared user library file for templates across Montage/Sequence/Live
   - For initial rollout, point all modes at the same file (e.g. reuse `montage-effects.json`) with no merge/migration

### paramsHash (determinism)

Implement by hashing a canonical, sorted representation:

- include effect order
- include effect `type`
- include all effect params (including `_enabled`)
- include chain-level `params`
- exclude `id`, `sourceTemplateId`, and `name`

Implementation approach:
- create an internal `Codable` payload struct with arrays + dictionaries
- encode with `JSONEncoder.outputFormatting = [.sortedKeys]`
- SHA256 the bytes

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `HypnoCore/Renderer/Effects/Core/EffectConfigSchema.swift` | `EffectChain`, `EffectDefinition` |
| `HypnoCore/Renderer/Effects/Library/EffectsSession.swift` | Current effects library persistence (today) |
| `HypnoCore/Renderer/Effects/Library/EffectChainsLibrary.swift` | Library storage (to be created) |
| `HypnoCore/Renderer/Effects/Core/EffectManager.swift` | Runtime coordination |
| `Hypnograph/Views/EffectsEditorView.swift` | UI for editing |
| `HypnoCore/Recipes/HypnogramRecipe.swift` | Recipe schema |

---

## Progress Log

- **2025-01-11**: Initial planning session. Defined two-tier model.
- **2025-01-13**: Major revision. New model: Current (applied to targets), Recent (history), Libraries (templates). Libraries are templates, recipes store copies. Bundled is bundled. Selection lives in Current section. Chain naming optional (auto-generated from effects). "Update Library Entry" vs "Save to Library..." actions.
- **2026-01-14**: MVR Step 1–2 implemented: `EffectChain` identity (`id`, `sourceTemplateId`, `paramsHash`) + explicit copy semantics; Effects editor now edits CURRENT (recipe) via `EffectManager` APIs; template edits no longer overwrite CURRENT by name; left panel uses sectioned `List` with RECENT stub.
- **2026-01-14**: MVR Step 3 implemented: global persistent RECENT store (deduped by `paramsHash`), capture replaced/cleared chains from `EffectManager`, and RECENT section UI (apply + remove).
- **2026-01-14**: MVR Step 4 implemented: templates are global across modes via a shared `EffectsSession` (`effects-library.json`).
