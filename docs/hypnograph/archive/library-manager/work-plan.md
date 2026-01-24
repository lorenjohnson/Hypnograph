# WORK PLAN — Hypnograph Library Manager (Concise)

GOAL:

Prepare Hypnograph for reuse across multiple apps (authoring, viewer, divine)
and introduce a shared Library Manager system for Treatments and Hypnogram Sets.

## STEP 1 — Stabilize and decouple reusable core

• Ensure all domain data types and file formats live outside the app UI layer.
• Separate pure data + rendering pipeline from any UI or app state.
• Core types must be UI-agnostic and Codable.

OUTPUT:

- A reusable Core module containing:
  - Hypnogram recipes and sources
  - Treatments and effects
  - No SwiftUI / AppKit / UIKit dependencies

## STEP 2 — Introduce Library domain types (no UI yet)

• Adopt terminology:
  - Treatment (formerly effect chain)
  - TreatmentLibrary
  - HypnogramSet
• Introduce a generic collection pattern for ordered sets with per-item metadata.
• Use the “middle-ground” approach:
  - Generic collection types
  - Alias only the top-level documents (not item types)
• Define JSON-serializable schemas for:
  - TreatmentLibrary documents
  - HypnogramSet documents
• No UI work in this step.

OUTPUT:

- Codable data structures
- Clear file-format ownership for treatments and hypnogram sets

## STEP 3 — Implement Library Manager UI (later)

• Build a shared Library Manager shell:
  - Left pane: ordered list of items (rename, reorder, select)
  - Right pane: domain-specific editor
• Plug in:
  - Treatments editor (effects list)
  - Hypnogram set editor (sources/layers list)
• Persistence via load / merge / save / autosave.

OUTPUT:
- Two library manager views using the same interaction grammar
- No duplication of collection logic

# ADDENDUM — DATA SCHEMA (Middle-Ground Approach)

## Generic collection primitives (Core)

struct CollectionItem<Value: Codable & Identifiable, Meta: Codable>: Codable, Identifiable {
    var id: UUID
    var label: String?
    var meta: Meta?
    var value: Value
}

struct CollectionDocument<Item: Codable & Identifiable>: Codable {
    var items: [Item]            // array order == UI order
}

## Treatments domain

struct Treatment: Codable, Identifiable {
    var id: UUID
    var name: String
    var effects: [Effect]        // ordered
    // future: timing, output hints, etc.
}

struct Effect: Codable, Identifiable {
    var id: UUID
    var type: String
    var enabled: Bool
    var params: [String: Double]?
}

struct TreatmentItemMeta: Codable {
    var pinned: Bool = false
    var notes: String?
}

// Top-level alias only
typealias TreatmentLibrary =
    CollectionDocument<CollectionItem<Treatment, TreatmentItemMeta>>

## Hypnogram sets domain

struct HypnogramEntry: Codable, Identifiable {
    var id: UUID
    var recipeRef: RecipeRef?          // MVP preferred
    var recipeInline: HypnogramRecipe? // optional later
    // future: artifacts, status
}

struct RecipeRef: Codable {
    var relativePath: String
}

struct HypnogramRecipe: Codable, Identifiable {
    var id: UUID
    var sources: [Source]              // ordered
}

struct Source: Codable, Identifiable {
    var id: UUID
    var sourceRef: String              // file path / Photos id / etc.
    var blendMode: String
    var opacity: Double
    var enabled: Bool
}

struct HypnogramItemMeta: Codable {
    var lastRenderedAt: Date?
    var notes: String?
    var status: String?
}

// Top-level alias only
typealias HypnogramSet =
    CollectionDocument<CollectionItem<HypnogramEntry, HypnogramItemMeta>>

---

# Refactor Progress (2025-12-31)

## Intent
Prepare Hypnograph for a future core module by:
- Moving recipe-related helpers out of Dream where appropriate.
- Converging on the new .hypno file extension.
- Keeping recipe normalization logic inside the recipe type.

## Work Completed in This Branch
- Added recipe file open/save UI helpers to centralize panel usage.
- Moved recipe normalization into `HypnogramRecipe`.
- Switched the recipe file extension to `.hypno` and kept `.hypnogram` backward compatible.
- Added recipe metadata fields (mode, createdAt, effectsLibrarySnapshot) and snapshot export handling.
- Wired quit prompt to save unsaved effect session changes.

## Files Touched (This Branch)
- Hypnograph/RecipeStore.swift
- Hypnograph/RecipeFileActions.swift
- Hypnograph/Modules/Dream/Dream.swift
- Hypnograph/HypnogramRecipe.swift
- Hypnograph/HypnogramStore.swift
- Hypnograph/Views/EffectsEditorView.swift
- Hypnograph/EffectLibrary/EffectChainLibraryActions.swift
- Hypnograph/HypnographApp.swift
- Hypnograph/Info.plist
- Deleted: Hypnograph/HypnogramRecipe+Normalization.swift

## Open Questions / Next Steps
- Confirm whether the new recipe metadata fields should be part of the core module now or later.
- Decide how to rename schema/runtime effect types to align with the new domain terms.
- Plan the migration path into a shared core module (folder move vs Swift package).
