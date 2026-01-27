# Drag & Drop Reordering (Layers + Effect Chains)

**Created**: 2026-01-27  
**Status**: Proposal / Planning

## Summary

Add drag-and-drop reordering for:

1. **Layers list** (Right Sidebar → Composition tab)
2. **Effect Chains list** (Right Sidebar → Effect Chains tab / library)

This is primarily a UX refinement for beta: it should be simple, native-feeling SwiftUI drag/drop.

## Goals

- Reorder layers without opening a separate editor.
- Reorder effect chain templates in the library list.
- Keep the “Liquid Glass” styling intact (selected row style should match mockups).

## Layer Reordering Constraints

### First Layer Special-Case (Blend Mode)

Current behavior: the first layer’s blend mode is fixed (grayed out), which is correct.

However:
- The first layer currently also disables opacity. We’d like to allow **opacity** for the first layer if possible (without re-architecting).
- Once reordering is enabled, a layer that previously had a non-`Normal` blend mode could become the first layer:
  - The UI might still show its prior blend mode even though it won’t apply as layer 0.

#### Proposed Behavior

- When a layer becomes index 0, force effective blend mode to `Normal` for rendering.
- UI for blend mode at index 0:
  - Either show “Normal” (fixed) always, or show the stored value but annotate it as inactive.
  - Prefer “Normal” always to reduce cognitive dissonance.

### Opacity for First Layer

If feasible:
- Allow opacity slider for layer 0.
- Rendering should simply apply opacity when compositing the base layer (currently base-layer handling is special-cased).

If not feasible in beta:
- Keep disabled, but document why and revisit after drag-drop ships.

## Effect Chain Reordering

- Reorder within the library list (not within a chain’s effects; that’s separate).
- Persist the order (session/library storage).

## Acceptance Criteria

- Layers can be dragged to reorder; selection stays sane; no crashes.
- Effect chains can be dragged to reorder; order persists.
- First-layer rules are clear and don’t mislead the user (blend mode + opacity behavior is intentional).

## Likely Touchpoints

- `Hypnograph/Views/RightSidebarView.swift` (layers list)
- `Hypnograph/Views/Components/LayerRowView.swift` (row styling / drag affordance if needed)
- `Hypnograph/Views/Components/EffectChainLibraryView.swift` (effect chain list)
- `HypnoCore` models/persistence for effect chain ordering

