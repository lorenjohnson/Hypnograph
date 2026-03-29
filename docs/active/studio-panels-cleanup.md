---
doc-status: draft
---

# Studio Panels Cleanup

## Overview

This project is a focused cleanup pass for the floating Studio panels and their remaining behavior issues after the recent windowing and panel work. The goal is not a new windowing architecture, but a concentrated batch of fixes and refinements to panel behavior, sizing, positioning, and overall feel.

One known issue already belongs here: panel size and/or position can sometimes change unexpectedly when switching between hypnograms. That behavior has shown up intermittently during the recent panel work and needs to be treated as a real bug rather than as acceptable panel drift. Panel height behavior is also a specific point of attention for this project.

This project is intentionally being opened in `draft` status so additional panel-cleanup notes can be accumulated after another careful review. The write-up should therefore act as a staging area for the next batch of panel-focused polish rather than assuming the current list is complete.

## Rules

- MUST treat panel sizing and positioning regressions as the primary scope of this cleanup pass.
- MUST include the known bug where panel size or position can change unexpectedly when switching hypnograms.
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
