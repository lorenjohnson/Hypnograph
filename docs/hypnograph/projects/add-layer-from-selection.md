# Add Layer From Selection (File / Photos Asset)

**Created**: 2026-01-27  
**Status**: Proposal / Planning

## Summary

Today we can add a **Random** layer. We also need a first-class way to add a layer by:

- Selecting a specific **file** (photo/video) from disk
- Selecting a specific **Apple Photos asset** (ideally by asset ID, not by copying/exporting)

This should be wired into the existing **Layers → + menu** in the right sidebar (Composition tab), where “Select Source…” currently exists but is disabled.

## MVP (Beta Scope)

### Option A (Preferred): One Standard Picker, Smart Handling

1. Open a standard macOS picker (likely `NSOpenPanel`).
2. If the selection is a normal file URL, add the layer as that file.
3. If the selection corresponds to an Apple Photos asset, store the **asset identifier** and treat it as a Photos-backed clip.

Open questions:
- Does `NSOpenPanel` (with Photos integration) provide a stable Photos asset identifier, or only a file URL / security-scoped bookmark to an exported copy?

### Option B (Fallback MVP): Explicit Photos Picker + File Picker

If the standard picker can’t yield asset IDs reliably:

- “Select Source…” opens a small choice:
  - “From Files…” → `NSOpenPanel`
  - “From Photos…” → PhotoKit picker flow that yields `PHAsset.localIdentifier`

This is more explicit but predictable.

## Non-Goals (for Beta)

- Multi-select add of many layers at once (nice-to-have later)
- Deep Photos library management UI in the sidebar
- Replacing the existing Photos selection window feature (can be revisited)

## Acceptance Criteria

- Selecting a file adds a new layer and starts playing as expected.
- Selecting a Photos asset adds a layer that remains linked to that asset (not a copied temp file), if possible.
- Works in Preview mode; respects Live-mode restrictions if any.

## Implementation Notes

- Entry point UI: right sidebar “Layers” header `+` menu.
- Likely code touchpoints:
  - `Hypnograph/Views/RightSidebarView.swift` (menu action wiring)
  - `HypnoCore` / media resolution layer for Photos asset vs file URL handling
- If we must support Photos via PhotoKit:
  - Use `PHAsset` local identifiers as the stable reference.

