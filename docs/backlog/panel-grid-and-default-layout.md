---
doc-status: draft
---

# Panel Grid and Default Layout

## Overview

This project explores a stronger layout model for the floating studio panels without turning them into a fully different docking system. The current panel behavior already gestures toward snapping, but it does not feel strong or intentional enough yet, especially around top alignment under the title bar and around reliably returning panels to useful positions.

The main user need is not just freer dragging. It is a lightweight sense of panel order and placement so the five panels can quickly fall into stable, expected positions around the main window. That likely includes stronger snap behavior, clearer default panel positions and sizes, and an easy way to restore the overall layout after the panels drift.

This should remain a spike for now because several details are still open. The reference feeling is closer to older Photoshop or Affinity panel behavior, but the current preference is still to keep these as window-like panels rather than fully converting them into a docked sidebar system.

## Rules

- MUST keep the current panel model recognizably window-like rather than turning this project into a full docking-system rewrite.
- MUST explore stronger snapping around the window edges, including the top edge under the title bar.
- SHOULD consider whether snap behavior wants a small margin from the edges rather than flush attachment.
- MUST define default positions and sizes for the five panels if that continues to look like the clearest way to reduce panel drift and disorder.
- MUST include a way to restore panels to their default layout, likely from the `View` menu.
- MAY explore an affordance on an individual panel for snapping it back to its default position.
- MUST coordinate with [studio-panels-cleanup.md](/Users/lorenjohnson/dev/Hypnograph/docs/active/studio-panels-cleanup.md) without letting that cleanup pass absorb this whole layout-model project.
- MUST NOT assume the Photoshop or Affinity reference pattern should be copied literally.

## Plan

- Smallest meaningful next slice: document the current snap behavior in plain language, especially which edges already snap, which do not, and where the title-bar alignment expectation currently breaks.
- Immediate acceptance check: the project should produce a clear candidate model for default panel positions and restore-layout behavior without yet committing to a full implementation.
- Follow-on slice: prototype stronger snapping and a restore-default-layout command, then evaluate whether the result feels helpful without making the panels feel over-constrained.

## Open Questions

- Should panel snapping be purely magnetic around edges, or should there also be named default slots for each panel?
- Does a small visual margin from the window edges feel more intentional than hard edge attachment?
- Should restore behavior act on all panels only, or should there also be a per-panel snap-back affordance?
- How much panel ordering logic is actually needed before this starts becoming a different window model?
