# Library Manager

**Project ID:** library-manager
**Status:** Planning
**Created:** 2025-12-31

## Overview

Prepare Hypnograph for reuse across multiple apps and introduce a shared Library Manager system for EffectChains and Hypnogram Sets. The Library Manager will provide a unified UI pattern for managing ordered collections of items.

## Current Implementation

The current effects management UI lives in:
- [EffectsEditorView.swift](../../../Hypnograph/Views/EffectsEditorView.swift) — The effects editor UI
- [EffectChainLibraryActions.swift](../../../Hypnograph/EffectChainLibraryActions.swift) — Library persistence actions

This project would generalize these patterns into a reusable Library Manager component.

## Plan

### Step 1 — Stabilize and decouple reusable core

- Ensure all domain data types and file formats live outside the app UI layer
- Separate pure data + rendering pipeline from any UI or app state
- Core types must be UI-agnostic and Codable

**Output:** A reusable Core module containing Hypnogram recipes, sources, and effects with no SwiftUI/AppKit/UIKit dependencies.

### Step 2 — Introduce Library domain types (no UI yet)

- Introduce a generic collection pattern for ordered sets with per-item metadata
- Use the "middle-ground" approach:
  - Generic collection types
  - Alias only the top-level documents (not item types)
- Define JSON-serializable schemas for:
  - EffectChainLibrary documents
  - HypnogramSet documents
- No UI work in this step

**Output:** Codable data structures and clear file-format ownership for effect chains and hypnogram sets.

### Step 3 — Implement Library Manager UI

- Build a shared Library Manager shell:
  - Left pane: ordered list of items (rename, reorder, select)
  - Right pane: domain-specific editor
- Plug in:
  - EffectChain editor (effects list)
  - Hypnogram set editor (sources/layers list)
- Persistence via load / merge / save / autosave

**Output:** Two library manager views using the same interaction grammar with no duplication of collection logic.

## Data Schema (Middle-Ground Approach)

### Generic collection primitives (Core)

```swift
struct CollectionItem<Value: Codable & Identifiable, Meta: Codable>: Codable, Identifiable {
    var id: UUID
    var label: String?
    var meta: Meta?
    var value: Value
}

struct CollectionDocument<Item: Codable & Identifiable>: Codable {
    var items: [Item]            // array order == UI order
}
```

### EffectChain domain

```swift
struct EffectChain: Codable, Identifiable {
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

struct EffectChainItemMeta: Codable {
    var pinned: Bool = false
    var notes: String?
}

// Top-level alias only
typealias EffectChainLibrary =
    CollectionDocument<CollectionItem<EffectChain, EffectChainItemMeta>>
```

### Hypnogram sets domain

```swift
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
```

## UI Requirements

From roadmap notes:

- [ ] Abstract for use by both the EffectChains Library and Hypnogram Sets
- [ ] Use a generalized Library Manager view that can be used by both
- [ ] You can add a Hypnogram recipe to a set or the currently displaying hypnogram to the set
- [ ] You can rename a set
- [ ] You can delete a set
- [ ] You can merge a set from disk into the existing set, or load it to replace the current set
- [ ] For Hypnogram sets this probably replaces the Favorites system for now
- [ ] To Favorite is to add a Hypnogram to the current set
- [ ] Hypnogram sets like EffectChain libraries are saved by default as the current session always, and can also be "Saved As" as well as explicitly opened from disk
- [ ] When opening another set you can choose to "Merge" it into the existing set
- [ ] The Library Manager allows drag and drop of items in the left panel
- [ ] You can re-order individual Hypnograms within a set

## Refactor Progress (2025-12-31)

Work completed in a previous branch:

- Added recipe file open/save UI helpers to centralize panel usage
- Moved recipe normalization into `HypnogramRecipe`
- Switched the recipe file extension to `.hypno` and kept `.hypnogram` backward compatible
- Added recipe metadata fields (mode, createdAt, effectsLibrarySnapshot) and snapshot export handling
- Wired quit prompt to save unsaved effect session changes

### Files touched

- `Hypnograph/RecipeStore.swift`
- `Hypnograph/RecipeFileActions.swift`
- `Hypnograph/Modules/Dream/Dream.swift`
- `Hypnograph/HypnogramRecipe.swift`
- `Hypnograph/HypnogramStore.swift`
- `Hypnograph/Views/EffectsEditorView.swift`
- `Hypnograph/EffectLibrary/EffectChainLibraryActions.swift`
- `Hypnograph/HypnographApp.swift`
- `Hypnograph/Info.plist`

## Open Questions

- Confirm whether the new recipe metadata fields should be part of the core module now or later
- Plan the migration path into a shared core module (folder move vs Swift package)
