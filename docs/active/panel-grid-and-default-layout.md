---
doc-status: in-progress
---

# Panel Grid and Default Layout

## Overview

This project is about making the floating studio panels restore and behave reliably enough that the current system can be trusted during long working sessions. The earlier framing around snapping and a stronger grid is still relevant, but the immediate issues are more basic: panel positions do not always restore against the final window state, the play bar can come back in the wrong place, and some panels are not sizing tightly enough to their actual content.

The first need is therefore not more layout cleverness. It is correctness and reliability. Panels need to restore in the right place after window and fullscreen restoration, panels whose content changes height need to trim and expand correctly, and the app needs explicit hooks for capturing and restoring meaningful default layouts.

Once those fundamentals are solid, this project can continue into stronger snapping behavior and, only if it still seems warranted, possibly a more locked or slot-like panel model. That later direction remains in scope as a possibility, but it is explicitly not the first slice of work.

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
