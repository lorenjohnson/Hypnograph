---
doc-status: in-progress
---

# Overview

Recent Apple Photos loading UX work added a compact top-right download HUD for PhotoKit-backed transfers, but in current testing some Apple Photos videos still appear blank with no visible status while they are waiting to resolve from iCloud. The likely current behavior is that Hypnograph only shows the HUD after PhotoKit emits explicit download-progress callbacks, while some slower or earlier loading phases do not emit those callbacks soon enough to keep the app from appearing inert.

This needs attention now because it reintroduces the exact trust problem that earlier Photos onboarding work was meant to reduce: the app can look broken even when it is still waiting on Apple Photos. The intended delta is to restore a small, quiet loading indicator whenever the current composition is blocked on Apple Photos-backed media, even if transfer progress has not yet started reporting.

## Rules

- MUST restore visible status for Apple Photos-backed composition loads before explicit transfer progress is available.
- MUST keep the UI quiet and compact rather than reintroducing a large blocking banner.
- SHOULD preserve real transfer progress when PhotoKit does report it.
- MUST NOT broaden this slice into a general loading-state redesign.

## Plan

- Smallest meaningful next slice: restore a fallback Apple Photos loading state for in-flight composition loads with unresolved Photos assets, and continue upgrading that state into progress when transfer callbacks arrive.
- Immediate acceptance check: when an Apple Photos video is selected and still downloading from iCloud, Hypnograph shows a visible loading indicator instead of a blank silent composition area.

## Open Questions

- Whether the fallback should remain purely indeterminate or show a distinct “loading” vs “downloading” visual treatment in the compact HUD.
