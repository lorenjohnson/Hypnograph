---
doc-status: draft
---

# Onboarding Photos Permission and Source Provisioning

## Overview

This project captured the top-priority onboarding failure around Apple Photos authorization and first-use source provisioning. On a fresh launch of a fresh build, Hypnograph was re-requesting Apple Photos permission more often than expected, which may itself indicate a regression in permission persistence or provisioning behavior for debug builds.

The more critical failure was what happened after permission was granted. The prompt appeared at an acceptable point in launch, but after granting full Apple Photos access the app could still land in the Studio showing the no-sources state as though Apple Photos had not actually provisioned yet. In practice, Apple Photos only appeared to become visible or usable after opening the Sources window, which made the first mile of the app feel unreliable exactly where it most needed to be solid.

The issue appears sufficiently resolved for now that it is no longer an active top-priority project. It still may deserve later testing and diligence, especially around fresh-install or debug-build edge cases, but the current behavior is good enough to clear out of the active queue.

## Rules

- MUST treat Apple Photos permissioning and first-use source provisioning as the primary onboarding issue to fix first.
- MUST verify whether repeated Apple Photos reprovisioning on fresh debug builds is expected behavior or a real regression.
- MUST make the post-permission launch path reliable so the app does not behave as though no Apple Photos source is available when access has just been granted.
- SHOULD keep the initial scope focused on first-mile trust and correctness rather than folding in unrelated Sources-window cleanup.
- MUST keep this document in `draft` until the current failure is reproduced and the first implementation slice is made explicit.

## Plan

- Smallest meaningful next slice: reproduce the fresh-build Apple Photos permission flow and document the exact state transitions before and after permission is granted.
- Immediate acceptance check: determine whether the bug is primarily repeated permission prompting, broken post-grant source provisioning, or both.
- Follow-on slice: implement the smallest fix that makes Apple Photos availability reflect granted permission immediately on the first-use path without requiring the Sources window to be opened manually.

## Open Questions

- Is the repeated Apple Photos prompt on fresh debug builds expected because of the build/install cycle, or is Hypnograph losing track of an already-granted authorization state?
- Was at least part of the observed repro caused by accidentally running more than one Hypnograph instance or build at once, especially if those instances did not present as the same effective app identity to macOS permissioning?
- After permission is granted, which part of startup is failing: source registration, media-library provisioning, UI refresh, or only the no-sources empty-state logic?
- Should the first-use path eagerly surface Apple Photos as a configured source immediately after permission is granted, or does it still require a separate source-selection step that the UI is failing to communicate clearly?
