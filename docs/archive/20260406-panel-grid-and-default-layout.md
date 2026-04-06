---
doc-status: completed
---

# Panel Grid and Default Layout

## Overview

This project was about making the floating studio panels restore and behave reliably enough that the current system could be trusted during long working sessions. The earlier framing around snapping and a stronger grid is still relevant, but the immediate issues were more basic: panel positions did not always restore against the final window state, the play bar could come back in the wrong place, and some panels were not sizing tightly enough to their actual content.

The first need was therefore not more layout cleverness. It was correctness and reliability. Panels needed to restore in the right place after window and fullscreen restoration, panels whose content changed height needed to trim and expand correctly, and the app needed explicit hooks for capturing and restoring meaningful default layouts.

This project is now complete enough to archive. The panel model is on a much firmer footing, the panel naming and structure cleanup has been folded into the same pass, and the remaining `Composition` resize bug is better understood even though it remains unresolved. Stronger snapping behavior and any later slot-like model can return as a separate follow-on project if they still feel necessary.

## Rules

- MUST keep the current panel model recognizably window-like rather than turning this project into a full docking-system rewrite.
- MUST first fix restore timing and placement correctness before spending effort on stronger snapping behavior.
- MUST make panel placement respond to the final restored window state, including native fullscreen restoration, rather than an earlier transient window size.
- MUST make content-driven panel sizing reliable, with `Sources` called out explicitly as an immediate case and `Composition` kept aligned with the same expectations.
- MUST add a way to capture the current panel layout as the app's default layout in debug builds, including positions and open/closed state.
- MUST add a user-facing way to restore panels to the current default layout.
- SHOULD also make room for a later user-saved default layout, separate from last-opened panel state.
- SHOULD treat any global loading veil during panel restoration as a later refinement, not as the first fix.
- MUST coordinate with [studio-panels-cleanup.md](/Users/lorenjohnson/dev/Hypnograph/docs/archive/20260330-studio-panels-cleanup.md) without letting that cleanup pass absorb this whole layout-model project.
- MUST NOT assume the Photoshop or Affinity reference pattern should be copied literally.

## Plan

- Smallest meaningful next slice: trace panel restoration timing against saved window state, fullscreen restoration, and play-bar placement so the panel calculations can happen against the correct final geometry.
- Immediate acceptance check: restored panels come back in stable, expected places, and the `Sources` panel trims to its content on load instead of opening taller than necessary.
- Follow-on slice: add a debug-only `save current layout as app default` path that captures positions plus open/closed state, then add a user-facing restore-default-layout command.
- Later slice: consider user-saved default layouts and only after that return to stronger snapping behavior.

## Open Questions

- How much of the current panel drift is caused by restore timing versus intentional position normalization against changing window sizes?
- Should default layout capture preserve literal positions only, or also preserve enough sizing assumptions that it remains meaningful across different screen sizes?
- Does the right user model eventually include both `restore app default layout` and `save my current layout as default`, or is one of those enough?
- Once restore correctness and default layout hooks exist, does stronger snapping still feel necessary or does the problem mostly recede?

## Known Issue

- `Composition` still has a small but visible polish bug when expanding or collapsing the global effect chain, nested effect rows, or layer rows: the panel content can briefly jump before settling, even though the final panel size and contents are functionally correct.
- This is not currently release-critical from a correctness standpoint. It is primarily a visual/jank issue in the resize-and-reflow sequence inside the `Composition` panel.

## Findings

- The panel host sizing math appears to be basically correct at this point. The panel usually lands on the right final height.
- The unresolved issue looks more like sequencing than measurement: inner composition content reflows first, then the outer panel resize catches up.
- The visual artifact survived a wide range of experiments, including:
  - host-side invalidation timing changes
  - top-pinned scroll and clip-view variants
  - non-scroll fit-to-content host variants
  - conditional scroll-host experiments
  - more AppKit-owned disclosure containers
  - a much more AppKit-owned `Composition` implementation
- The stronger-than-expected result from the AppKit experiments is that simply “moving more of it to AppKit” was not an immediate cure. The same broad sequencing pattern still showed up, just in different forms.
- The most useful current architectural takeaway is that this appears to be a seam around simultaneous inner content reflow plus outer floating-panel auto-sizing, not just a simple SwiftUI disclosure-transition bug.
- If this returns to priority later, the next work should start from that premise instead of restarting with generic host sizing tweaks.
