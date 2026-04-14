---
doc-status: draft
---

# Overview

Define a dockable-panel system for Studio so the remaining floating panels can optionally live inside fixed positions within the main window while preserving the current floating-panel behavior as an alternate presentation mode.

The immediate motivation is the panel model that is emerging around the new bottom dock and `Properties` panel. Hypnograph is moving toward fewer, stronger panels, and some of those panels will likely want stable homes along the left and right sides of the main window. That points toward a panel architecture where panel content can be hosted either:

- as a floating AppKit panel window, or
- as an embedded in-window docked panel.

This is separate from the current [bottom-dock-and-properties](../active/bottom-dock-and-properties.md) project. That active project is about making time-based interaction and settings clearer now. This backlog project is about the later host/presentation model for making panels dockable.

The likely first practical use is:

- the bottom play bar remains embedded at the bottom,
- `Properties` can dock into the upper-left area by default,
- other panels can optionally dock into left/right positions,
- and a menu command can dock all panels to their default homes.

# Scope

- MUST treat panel content and panel host/presentation as separate concerns.
- MUST preserve floating panel behavior as a supported mode.
- MUST support embedded docked panel hosts inside the main window.
- MUST assume a small fixed set of dock targets, likely two on the left and two on the right.
- MUST allow a menu action to dock all panels into default positions.
- SHOULD make docking feel like a smooth snap from a dragged floating panel into a dock target, even if the implementation swaps host type at drop time.
- SHOULD keep dock target rules simple and legible before exploring arbitrary free-form docking.
- SHOULD allow a single docked panel in a side column to take the full available height above the play bar.
- SHOULD allow two docked panels in one side column to divide available height, with room for later refinement when one panel has naturally smaller fixed content.
- MUST NOT block current bottom-dock-and-properties work on fully designing or implementing docking.
- MUST NOT assume every panel needs to be dockable everywhere.

# Plan

- Smallest meaningful next slice:
  - Capture the host-model decision and first-pass docking rules in one place so later implementation can stay coherent.
- Immediate acceptance check:
  - The project doc clearly describes floating vs embedded hosts, likely dock targets, default docking behavior, and the first-pass sizing rules for docked side panels.
- Likely implementation checkpoints later:
  - Introduce a host-agnostic panel content model.
  - Define dock target positions and default mappings per panel.
  - Add visual dock targets during panel drag.
  - Add drop-to-dock host conversion.
  - Add “Dock All Panels” command.

# Open Questions

- Should dock targets appear only when a dragged panel enters the main window, or immediately when any panel drag begins?
- Should all dock targets always be eligible, or should each panel advertise only a subset of allowed homes?
- How much animation is needed to make floating-to-docked host conversion feel continuous rather than like a disappearance/recreation?
- When a docked side column contains panels with very different natural heights, what is the simplest rule that still feels good in use?
