---
doc-status: done
---

# Sources Window Cleanup

## Overview

This project cleans up the first-mile source setup path after the recent Sources window and windowing refactors. The current behavior has two problems that now feel coupled enough to treat as one project.

First, Apple Photos authorization behavior has become unreliable. The app can fall into states where parts of the UI behave as though Photos access is missing even after access has already been granted, especially around opening a hypnogram or otherwise re-entering an already running session. That makes the first-use path feel inconsistent and untrustworthy, and it risks reintroducing the kind of repeated Photos-access prompting that was already fixed once on startup. The immediate cleanup direction is to consolidate authorization state and request handling, while still allowing the app to eagerly build the real media library when access already exists.

Second, the Sources window currently renders the full Apple Photos album list inline with source toggles. That makes the window heavier than it needs to be and turns a long album list into persistent clutter. The intended direction is a simpler Sources table that stores chosen Photos scopes as source rows, while album picking happens in a separate modal flow. The relevant reference interaction from Divine's settings modal at `../Divine/Divine/Views/AppSettingsView.swift` is specifically the Apple Photos album-selection modal plus the way saved Apple Photos sources are shown alongside file and folder sources in one table. Hypnograph does not need to match Divine's broader settings UI exactly.

## Rules

- MUST treat Apple Photos authorization consistency as the first implementation slice.
- MUST identify whether the current regression is caused by stale authorization state, an unnecessary re-request path, or a load-flow side effect when opening hypnograms.
- MUST make Sources-window Photos UI reflect granted authorization reliably without requiring relaunches or unrelated refreshes.
- SHOULD centralize Photos authorization refresh or observation enough to avoid split-brain UI state between the main window, No Sources state, and Sources window.
- MUST move Apple Photos album selection out of the always-rendered Sources window list and into a separate picker or modal flow.
- MUST preserve saved Photos selections as normal source rows in the Sources window after the picker closes.
- SHOULD reduce unnecessary Apple Photos album loading in the steady-state Sources window.
- MUST NOT expand this project into broader source-model redesign beyond the cleanup needed for the above behavior.

## Plan

- Smallest meaningful next slice: trace the current Photos authorization flow across launch, Sources window display, No Sources state, and hypnogram-open paths; then fix the inconsistent authorization state or repeated re-request behavior first.
- Immediate acceptance check: after granting Photos access once, opening the Sources window, hitting empty-source states, and opening hypnogram files should all continue to recognize existing access consistently without behaving like Photos access is missing.
- Follow-on slice: refactor the Sources window so Apple Photos selections are managed through a dedicated picker flow and displayed afterward as saved source rows rather than as a permanently expanded album list, using the Divine pattern in `../Divine/Divine/Views/AppSettingsView.swift` specifically for album-modal selection and unified saved-source rows.

## Open Questions

- Whether the cleanest fix lives entirely in Hypnograph app state or requires changes in the shared Photos integration layer.
- Whether the Photos picker for saved album scopes should reuse existing PHPicker-based infrastructure, or whether album selection needs a dedicated custom modal because PHPicker is asset-oriented rather than album-oriented.
