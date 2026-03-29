---
doc-status: draft
---

# Studio Panels Cleanup

## Overview

This project is a focused cleanup pass for the floating Studio panels and their remaining behavior issues after the recent windowing and panel work. The goal is not a new windowing architecture, but a concentrated batch of fixes and refinements to panel behavior, sizing, positioning, and overall feel.

One known issue already belongs here: panel size and/or position can sometimes change unexpectedly when switching between hypnograms. That behavior has shown up intermittently during the recent panel work and needs to be treated as a real bug rather than as acceptable panel drift. Panel height behavior is also a specific point of attention for this project.

Another concrete friction now belongs here: `Auto Hide Panels` currently leaks panels on launch even when it is enabled. Launch should begin with panels hidden until there is activity when auto-hide is on. Separately, the intended first-run product behavior is now that `Auto Hide Panels` defaults to `on` for a brand-new user.

The current `Tab` clean-screen instructional HUD has also outlived its place in the interface. For now, the preferred move is to disable or remove that message from normal presentation rather than redesign it immediately, while keeping open the possibility that the same general screen area could later host better contextual guidance.

This project is intentionally being opened in `draft` status so additional panel-cleanup notes can be accumulated after another careful review. The write-up should therefore act as a staging area for the next batch of panel-focused polish rather than assuming the current list is complete.

## Rules

- MUST treat panel sizing and positioning regressions as the primary scope of this cleanup pass.
- MUST include the known bug where panel size or position can change unexpectedly when switching hypnograms.
- MUST make app launch respect `Auto Hide Panels` so panels stay hidden until activity when that setting is enabled.
- MUST treat `Auto Hide Panels` defaulting to `on` for a brand-new user as part of the intended panel behavior.
- SHOULD remove or disable the current clean-screen instructional HUD until there is a clearer use for that surface.
- SHOULD pay particular attention to panel height behavior, especially where panel size is content-driven or changes across different hypnograms.
- SHOULD collect multiple small panel/window refinements into one cohesive cleanup pass rather than scattering them across unrelated projects.
- MUST preserve the current panel model and avoid expanding this project into a new windowing-system rewrite.
- MUST keep this document in draft until the next round of panel review notes has been added.

## Plan

- Smallest meaningful next slice: capture the currently known panel sizing/positioning bug and then append the next batch of panel-review notes before deciding the first implementation slice.
- Immediate acceptance check: after the next review pass, this draft should contain a concrete list of panel issues worth fixing together, rather than only a vague placeholder for future cleanup.
- Follow-on slice: once the issue list is complete enough, move the document out of draft and begin with the highest-signal panel regression, likely the hypnogram-switch size/position drift.

## Open Questions

- Which of the current panel issues are truly one bug with multiple symptoms versus separate cleanup items that only appear related?
- Whether panel height behavior needs small targeted fixes or one deeper pass through the panel sizing rules.
