# MVR Implementation Plan (Code-Level)

This is a more implementation-oriented companion to `docs/projects/20250111-effects-system-refactor.md`.

Scope note:
- “CURRENT” is per-mode (Montage/Sequence/Live each has its own active recipe).
- “LIBRARIES” and “RECENT” are intended to be global across modes.

This doc expands the Minimum Viable Refactor (MVR) into concrete code-level steps, call-site changes, and validation.
Treat it as the execution checklist; keep the main spec doc focused on UX and architecture.

---

## Where we are today (why MVR exists)

Current behavior couples “templates” (library) and “applied” (recipe) by **name**:

- UI chooses a library chain by index, then applies a `copy()` into the recipe.
- Parameter editing updates the **library session** (`EffectsSession.updateParameter(...)`) which triggers:
  - `DreamPlayerState.setupEffectsSession()` → `effectsSession.onChainUpdated` → `effectManager.reapplyActiveEffects()`
  - `EffectManager.reapplyActiveEffects()` replaces the recipe’s chain by matching **`name`**

Net result: editing a chain mutates the library and then overwrites the recipe’s “working copy”.

MVR’s core promise: **editing in CURRENT edits the recipe’s applied chain**, while libraries remain templates.

Relevant code references (current):
- `Hypnograph/Views/EffectsEditorView.swift` (selection + parameter editing currently targets `EffectsSession`)
- `HypnoCore/Renderer/Effects/Library/EffectsSession.swift` (template persistence + mutation APIs)
- `HypnoCore/Renderer/Effects/Core/EffectManager.swift` (`reapplyActiveEffects()` does name-based overwrites)
- `Hypnograph/Dream/DreamPlayerState.swift` + `Hypnograph/Dream/LivePlayer.swift` (wire sessions into managers)

---

## Implementation Order (Steps 1–4)

Given risk and isolation, the recommended order is:

1. Step 1: Identity + explicit copy semantics
2. Step 2: Working copy editing + sectioned List UI
3. Step 3: RECENT store (global) + wiring (capture replaced/cleared)
4. Step 4: Global LIBRARIES store across modes (no merge/migration required)

This ordering keeps the app working after each step and defers the cross-mode wiring change until the end.

Status:
- ✅ Step 1 implemented (2026-01-14)
- ✅ Step 2 implemented (2026-01-14)
- ✅ Step 3 implemented (2026-01-14)
- ✅ Step 4 implemented (2026-01-14)

---

## Step 1 — Identity + explicit copy semantics

### Goal

Add identity + template linking without breaking existing meaning of `copy()` call sites (exports, snapshots, etc.).

### Primary changes

**File:** `HypnoCore/Renderer/Effects/Core/EffectConfigSchema.swift`

1) Add to `EffectChain`:
- `public var id: UUID`
- `public var sourceTemplateId: UUID?`
- `public var paramsHash: String { ... }` (computed)

2) Update Codable model:
- The implementation does not need to preserve compatibility with old `.hypno` recipes or older effects JSON formats.
- It is acceptable to treat incompatible on-disk data as “reset to defaults”.

3) Adopt a simple, explicit 2-operation model for “copying”:

**A. `clone()`** (same identity, new object)
- deep copies `effects`/`params`, does NOT copy runtime cache
- preserves `id`
- preserves `sourceTemplateId`
- does NOT copy `_instantiatedEffects` (new instance always starts with an empty cache)

**B. `init(duplicating:sourceTemplateId:)`** (new identity, template link explicit)
- deep copies `effects`/`params`, does NOT copy runtime cache
- generates a new `id = UUID()`
- `sourceTemplateId` is provided explicitly (often `nil` or the template’s `id`)
- does NOT copy `_instantiatedEffects` (new instance always starts with an empty cache)

Notes:
- Avoid `init(from:)` naming because Swift uses `init(from decoder:)` for `Decodable`.
- If you prefer a factory method, use `static func duplicate(_ chain:sourceTemplateId:)`.

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

### Why this matters for “still works”

This is the foundation that later steps rely on:
- RECENT dedupe
- template linking (“Update Library Entry” later)
- safe unification of templates into a global library

### Validation

- Save and reload: confirm new fields persist.
- Confirm a fresh install path works (no existing files present).

Completed:
- `EffectChain.id`, `EffectChain.sourceTemplateId`, `EffectChain.paramsHash`
- `EffectChain.clone()` (same identity) + `EffectChain.init(duplicating:sourceTemplateId:)` (new identity)

---

## Step 2 — Working copy editing (CURRENT edits recipe)

### Goal

Parameter editing / add / remove / reorder should mutate the applied recipe chain (CURRENT), not the template library chain.

### Core behavioral changes

1) Stop “template edits” from overwriting CURRENT by name.
2) Ensure UI edits flow through `EffectManager`’s recipe mutation APIs.
3) Make “Update Library Entry” depend on template writability; provide “Copy to My Effects” when it isn’t.

### UI work (left panel)

As part of Step 2, move the left side to a single sectioned SwiftUI `List` so later RECENT + LIBRARIES work is additive:

- `List` with `Section` blocks:
  - CURRENT (Global + sources from the active recipe)
  - RECENT (can be empty/stub initially)
  - LIBRARIES (My Effects + Bundled)
- `List(selection:)` should bind to “selected target” (Global/Source N), not to a template row.
- Row context menus map directly to the actions in the spec.

Note on “New Effect”:
- Remove the “+” New Effect Chain button
- Each target always has an (possibly empty) chain in the recipe; users start from “None” by adding effects in the right panel.

### Key code changes

**File:** `Hypnograph/Dream/DreamPlayerState.swift`

Today:
- `effectsSession.onChainUpdated` and `onReloaded` call `effectManager.reapplyActiveEffects()`

Change:
- remove these callbacks, or gate them so they never overwrite CURRENT.
  - simplest for Step 2: do nothing on template updates (user must re-apply a template to see new template values)

This is the single highest-leverage “stop the bleed” change.

**File:** `Hypnograph/Dream/LivePlayer.swift`

Do the same change there (Live also wires an `EffectsSession` and has onChainUpdated/onReloaded callbacks).

**File:** `Hypnograph/Views/EffectsEditorView.swift`

Today (simplified):
- effect list is `viewModel.effectChains` (from `EffectsSession`)
- parameter edits call `viewModel.updateParameter(effectIndex: selectedEffectIndex, ...)`
- `viewModel.updateParameter(...)` persists to `EffectsSession.updateParameter(...)` (template mutation)

Change:
- Replace the left panel with a sectioned SwiftUI `List`:
  - CURRENT rows are targets from the active recipe (Global + Source N)
  - RECENT rows are snapshots
  - LIBRARIES rows are templates (My Effects + Bundled)
  - selection lives in CURRENT (target selection), not in template rows
- Route parameter edits to the recipe via `dream.activeEffectManager` methods:
  - `updateEffectParameter(for layer: Int, effectDefIndex: Int, key: String, value: AnyCodableValue)`
  - `addEffectToChain(for layer: Int, effectType: String)`
  - `removeEffectFromChain(for layer: Int, effectDefIndex: Int)`
  - `reorderEffectsInChain(for layer: Int, fromIndex: Int, toIndex: Int)`
  - `setEffectEnabled(...)`, `resetEffectToDefaults(...)`, `randomizeEffect(...)`

Net: the right-hand “params” panel edits CURRENT.

### Applying templates without churning IDs

This is subtle once IDs exist:

- You do NOT want every slider tick to create a new UUID.
- So “apply template” and “edit current chain” must be distinct operations.

Suggested change:

**File:** `HypnoCore/Renderer/Effects/Core/EffectManager.swift`

Add a method dedicated to applying templates:
- `public func applyTemplate(_ template: EffectChain?, to layer: Int)`
  - capture the current (possibly user-tweaked) chain for RECENT *before* replacing it (later step; only if non-empty)
  - if template != nil:
    - create a new recipe-owned instance:
      - `EffectChain(duplicating: template, sourceTemplateId: template.id)`
  - set on recipe via setters
  - if template == nil:
    - clear chain on recipe

Update the UI selection path to call `applyTemplate(...)` instead of `setEffect(from:for:)`.

Keep `setEffect(from:for:)` for internal recipe updates only.

### “Still works” checklist after Step 2

- Selecting an effect from the list still applies it.
- Tweaking params updates the preview/live output.
- Switching Montage/Sequence/Live still works (because they still have per-mode recipes).
- Template library edits no longer unexpectedly alter CURRENT.
- Applying from Bundled behaves like any other template apply; updating Bundled templates is not allowed.

### Validation (manual)

- Apply template, tweak params, switch away and back: CURRENT retains tweaks.
- Edit template library (if still possible anywhere), observe CURRENT does not change.
- Save recipe, restart app, restore recipe: CURRENT still has tweaked values.

Completed:
- UI edits now route through `EffectManager` recipe mutation APIs (CURRENT is the working copy).
- Template library updates no longer trigger name-based overwrites into the recipe.
- Left panel converted to a sectioned `List` with CURRENT/RECENT/LIBRARIES (RECENT stubbed until Step 3).

---

## Step 3 — RECENT store (global) + wiring

### Goal

Global “recently replaced/cleared chains” history, deduped by paramsHash, shared across modes.

### Data design

Add a new persistent store:

**New file (likely):** `HypnoCore/Renderer/Effects/Library/RecentEffectChainsStore.swift`

Use `PersistentStore<RecentEffectChainsConfig>` where:

```swift
struct RecentEffectChainsConfig: Codable {
  var version: Int
  var entries: [RecentEntry]
}

struct RecentEntry: Codable, Identifiable {
  var id: UUID
  var chain: EffectChain
  var timestamp: Date

  // Optional UX helpers
  var sourceTemplateId: UUID?
  var templateNameHint: String?
  var variantHint: String? // e.g. short hash suffix
}
```

Exact-dedupe key should be `chain.paramsHash` (not entry id).

### Variant indication (pragmatic MVR approach)

Keep this hash-only in MVR: RECENT uses `paramsHash` for exact-dedupe and a lightweight variant indicator.

- Always display the effects list subtitle (already planned UX).
- Add a small, stable variant hint:
  - `Variant · <hashSuffix>` where `<hashSuffix>` is first 4–6 chars of `paramsHash`
  - If `sourceTemplateId != nil`, you may optionally render it as `Template Name · <hashSuffix>` (still hash-only).

### Update vs Copy actions (Current/Recent menus)

These actions operate on the CURRENT recipe chain, not the template.

- **Update Library Entry**: only available when `sourceTemplateId` points to an existing **writable** template.
- **Copy to My Effects**: available when Update is not available; creates a new template in "My Effect Chains" and sets
  the CURRENT chain’s `sourceTemplateId` to that new template’s UUID.

Writability rule (for now):
- A template is writable if its owning library is not bundled (e.g. `isBundled == false`).

### Name-based APIs to audit

The current codebase has name-based behaviors that must not overwrite CURRENT once Step 2 lands:

- `EffectManager.reapplyActiveEffects()` (name-based replacement) should not run in response to template edits.
- `EffectsSession.merge(...)` overwrites by name; it is fine as a temporary import utility but should not be used as a “linking” mechanism between CURRENT and templates.

Plan: after Step 2, audit call sites that rely on name matching for effect selection or reapplication and remove/gate them.

### Wiring points (where RECENT gets populated)

You want RECENT to capture the chain being replaced/cleared, regardless of mode or target.

Best central point:

**File:** `HypnoCore/Renderer/Effects/Core/EffectManager.swift`

In `applyTemplate(_:to:)` (added in Step 2):
- get current chain for `layer` from recipe
- if it’s non-empty, ask recentStore to add it (dedupe)
- then apply the new template instance

In `clearEffect(for layer:)`:
- capture existing chain into RECENT before clearing

To make it global:

**File:** `Hypnograph/Dream/Dream.swift`
- construct one `RecentEffectChainsStore` instance (shared)
- inject into `montagePlayer.effectManager`, `sequencePlayer.effectManager`, and `livePlayer.effectManager`

### Validation

- Apply A → tweak → apply B: A appears in RECENT.
- Clear current: cleared chain appears in RECENT.
- Switch modes: RECENT list is the same.
- Restart app: RECENT persists.

Completed:
- Added global persistent `RecentEffectChainsStore` (deduped by `paramsHash`, capped at 100).
- Wired `EffectManager.applyTemplate` + `EffectManager.clearEffect` to capture replaced/cleared chains into RECENT.
- Injected the shared store into Montage/Sequence/Live effect managers.
- Implemented RECENT section UI in the effects editor (apply + remove).

---

## Step 4 — Global LIBRARIES store across modes

### Goal

Templates are global across Montage/Sequence/Live. CURRENT remains per-mode.

### Key decision

Use ONE canonical library store (file) for templates going forward (e.g. `effects-library.json`).

### Implementation sketch

**New file:** `HypnoCore/Renderer/Effects/Library/GlobalEffectsLibrary.swift` (name flexible)

- A dedicated `EffectsSession` (or new store type) backed by the global file.
- All decks use this for template browsing and “apply template”.

**File:** `Hypnograph/Dream/Dream.swift`

- Create a `globalEffectsLibrary` store once.
- Replace `DreamPlayerState.effectsSession` and `LivePlayer.effectsSession` usage in the editor with the shared store.

**No migration (initial rollout)**

For initial rollout, do not merge existing per-mode libraries. Instead:

- Choose a single canonical user library file (e.g. reuse `montage-effects.json` or rename to `effects-library.json`)
- Point Montage/Sequence/Live to that one file for template browsing and apply
- Leave any existing per-mode files untouched/unused

### Validation

- Template list is identical regardless of mode.
- Applying templates works in all modes.

Completed:
- Added a single shared `EffectsSession` (`effects-library.json`) and injected it into Montage/Sequence/Live.
- The effects editor now browses/saves/loads templates against the shared library session.

---

## Risk register (why this isn’t “just a few hours”)

1) The current system is “template-driven”: edits to `EffectsSession` trigger name-based overwrites into the recipe.
   - MVR must remove/replace that behavior without breaking live updates.

2) Applying templates vs editing CURRENT must not churn UUIDs.
   - Requires new, explicit entry points (don’t overload `copy()`).

3) Global library unification must keep template IDs stable.
- If template IDs change, `sourceTemplateId` becomes meaningless.

4) Multi-mode wiring is non-trivial:
   - Montage/Sequence/Live each have their own players/managers, so shared stores must be injected carefully.

---

## Updated estimate (AI-assisted)

Assuming we implement Steps 1–4 in order and keep UI changes minimal:

- Step 1: 5–9 hours
- Step 2: 8–14 hours
- Step 3: 5–9 hours
- Step 4: 2–5 hours

Total: **20–37 hours** (about **3–5 focused days**).

Practical note: Step 2 (List UI + selection model) tends to be the spikiest; budget ~+1–2 days of slack if you want a comfortable schedule.

If you explicitly defer Step 4 (global libraries) to later, then “MVR-lite” (Steps 1 → 2 → 3) is:
- **18–32 hours**

These ranges assume normal iteration + manual verification across Montage/Sequence/Live.
