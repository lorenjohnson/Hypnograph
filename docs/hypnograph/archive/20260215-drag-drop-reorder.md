# Drag & Drop Reordering (Layers + Effect Chains)

**Created**: 2026-01-27  
**Completed**: 2026-02-15  
**Status**: Archived

> Implemented:
> - Drag/drop reordering for layer rows in the right sidebar composition tab (implicit row-body drag, no drag handle).
> - Drag/drop reordering for effect chain library rows (implicit row-body drag, no drag handle) with persisted order.
> - Layer index `0` blend mode treated as effective `Normal` while preserving stored non-normal values for restoration when moved out of index `0`.
> - Layer index `0` opacity remains editable (base compositing path supports this).

## Summary

Add drag-and-drop reordering for:

1. **Layers list** (Right Sidebar → Composition tab)
2. **Effect Chains list** (Right Sidebar → Effect Chains tab / library)

This is primarily a UX refinement for beta: it should be simple, native-feeling SwiftUI drag/drop.

## Goals

- Reorder layers without opening a separate editor.
- Reorder effect chain templates in the library list.
- Keep the “Liquid Glass” styling intact (selected row style should match mockups).

## Drag Interaction Model (MVP)

- No dedicated drag handles for now.
- Drag should start from the row body/background (implicit drag affordance).
- Existing row controls (buttons, toggles, pickers, menus) should keep normal behavior and not accidentally start drags.
- Applies to both layers rows and effect chain library rows.

## Layer Reordering Constraints

### First Layer Special-Case (Blend Mode)

Current behavior: the first layer’s blend mode is fixed (grayed out), which is correct.

However:
- The first layer currently also disables opacity. We’d like to allow **opacity** for the first layer if possible (without re-architecting).
- Once reordering is enabled, a layer that previously had a non-`Normal` blend mode could become the first layer:
  - The UI might still show its prior blend mode even though it won’t apply as layer 0.

#### Proposed Behavior

- When a layer becomes index 0, treat its effective blend mode as `Normal` for rendering.
- Preserve the layer's previously selected blend mode value in the model while it is at index 0.
- Blend mode UI at index 0 should be non-editable and display fixed `Normal`.
- If the layer is moved back out of index 0, its previously stored blend mode becomes active and editable again.

### Opacity for First Layer

If feasible:
- Allow opacity slider for layer 0.
- Rendering should simply apply opacity when compositing the base layer (currently base-layer handling is special-cased).

If not feasible in beta (for example if base-layer compositing semantics make index 0 opacity effectively non-adjustable without special-case hacks):
- Keep layer-0 opacity editing disabled (no workaround tricks for this release).
- Preserve whatever opacity value is stored on that layer in the model while it is at index 0.
- If the layer is moved back out of index 0, its previously stored opacity value becomes active/editable again.
- Document the constraint and revisit after drag-drop ships.

## Effect Chain Reordering

- Reorder within the library list (not within a chain’s effects; that’s separate).
- Persist the order (session/library storage).

## Acceptance Criteria
- No extra drag handle icon for now; dragging from row body works for both layers and effect chain entries.
- Layers can be dragged to reorder; selection stays sane; no crashes.
- Effect chains can be dragged to reorder; order persists.
- First-layer rules are clear and don’t mislead the user (blend mode + opacity behavior is intentional).
- If layer-0 opacity is not feasible, stored opacity is still retained and restored when moved out of index 0.

## Likely Touchpoints

- `Hypnograph/Views/RightSidebarView.swift` (layers list)
- `Hypnograph/Views/Components/LayerRowView.swift` (row styling / drag affordance if needed)
- `Hypnograph/Views/Components/EffectChainLibraryView.swift` (effect chain list)
- `HypnoCore` models/persistence for effect chain ordering
