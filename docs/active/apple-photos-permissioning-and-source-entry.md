---
doc-status: in-progress
---

# Apple Photos Permissioning and Source Entry

## Overview

This project is about restoring trust in the Apple Photos entry path before treating optimized storage as the main problem.

Right now the most important problem appears to be a real authorization/bootstrap bug, not the broader onboarding refinement work. In some states, Hypnograph appears to boot as though Apple Photos is already an active source, triggers or depends on authorization during launch, and then gets into a temporarily broken or confused state before it catches up.

This project now has three slices, in this order:

1. Fix the bug around launch-time Apple Photos authorization and stale Apple Photos source state.
2. Refine the true first-launch / no-permission empty state so the next step is obvious and coherent.
3. Simplify Apple Photos source entry so `All Items`, albums, and `Custom Selection` are all chosen through one clearer flow.

The wider concerns around optimized storage, slow cloud-backed loading, and local disk usage are still real. They remain on the map as background context, but they are not the first thing to solve in this project because the current permissioning bug is likely obscuring the actual user experience underneath.

Current concrete failure modes already observed:

- On a true fresh launch, Hypnograph currently does not auto-request Apple Photos access; instead it surfaces explicit `Request Photos Access` actions in the no-sources UI and Sources window.
- In some launch states, Apple Photos appears to be treated as an already relevant source before authorization state has fully settled.
- A likely high-priority bug case is: `Apple Photos: All Items` is already persisted as an active source, Apple Photos is no longer authorized, and launch then triggers authorization or startup recovery work in a bad order.
- That state may explain why some beta users are seeing a Photos re-authorization request during startup and then a temporary broken or confused app state right afterward.
- If the user rejects Apple Photos permission at first launch, the app can still appear to retain `Apple Photos All Items` as an active source.
- In that state, Hypnograph can continue trying to render Apple Photos-backed content and simply appear broken or blank instead of failing clearly.
- The Sources window does show a way to request Apple Photos permission again, but that action does not currently behave reliably.
- At least part of the bad state may be compounded by reopening onto a previous history item whose sources depended on earlier Apple Photos access.
- After some interaction inside the same session, the app can eventually settle into a more correct no-sources state, where trying to generate a new composition simply shows the no-media-sources screen again.
- That suggests the likely critical bug is narrower than originally thought: the initial launch / re-authorization transition appears to be wrong, while later steady-state no-sources behavior may already be closer to correct.

## Rules

- MUST treat Apple Photos permissioning and first-use source entry as the current implementation focus.
- MUST treat the launch-time authorization / stale-source bug as the first slice inside that focus.
- MUST make the post-grant path reliable so the app does not behave as though Apple Photos is still unavailable immediately after permission is granted.
- MUST provide a clear recovery path in the Sources window when Apple Photos is not yet authorized, has been denied, or was canceled.
- MUST ensure unauthorized Apple Photos sources do not remain active as though they were usable.
- MUST keep Apple Photos central to the product story for now.
- SHOULD keep the UI for choosing Apple Photos scope coherent and lightweight.
- SHOULD use existing source-selection UI where possible instead of creating a whole new onboarding framework immediately.
- SHOULD improve the local debugging workflow enough that Photos permissioning can be reset and re-tested repeatedly without wiping the normal app's real state.
- MUST keep on the map the broader optimized-storage concerns:
  - slow loading of cloud-backed assets
  - unclear first-run waiting behavior
  - local disk usage implications
  - possible filesystem-derived locality signals from the Photos library bundle
- MUST NOT let those broader concerns distract the first slice away from fixing the current permissioning and source-entry bug.

## Scope

- MUST first trace and fix the launch path where Apple Photos sources and Apple Photos authorization state can disagree or settle in the wrong order.
- MUST verify what happens when `Apple Photos: All Items` is already persisted as a source but Apple Photos permission is no longer granted.
- MUST determine whether current beta re-authorization behavior is being triggered by persisted source state, app version/build churn, or something else in startup.
- MUST verify what happens on first launch when Apple Photos permission is:
  - granted
  - denied
  - canceled
- MUST then make the first-launch empty state and Sources window able to surface Apple Photos authorization as an obvious next action when permission is missing.
- MUST make unauthorized Apple Photos-backed content fail clearly rather than silently rendering as broken or blank playback.
- MUST review the Apple Photos source-entry flow so it is clearer whether the user is choosing:
  - `All Items`
  - or a specific album
- SHOULD collapse the current multi-level Apple Photos source menu so the user chooses `Apple Photos` once, then completes the choice in a dedicated modal.
- SHOULD make that modal handle:
  - `All Items`
  - album selection
  - `Custom Selection` via the native Photos picker
- MAY reuse the existing album list UI if that gets to a clear result quickly enough.

## Plan

- Smallest meaningful next slice: reproduce and trace the launch-time bug where Apple Photos source state and Apple Photos authorization state can get out of sync, especially when `Apple Photos: All Items` is already persisted.
- Smallest meaningful next slice: use the new debug reset path to repeatedly test:
  - clean first launch
  - launch with prior Photos authorization
  - launch with Apple Photos sources persisted but Photos permission no longer granted
- Immediate acceptance check: launch no longer enters a confused state when Apple Photos source state and authorization state disagree, and unauthorized Apple Photos sources do not behave as though they are usable.
- Follow-on slice: refine the true first-launch / no-permission UI so the no-sources screen and Sources window are coherent and clearly guide the user into authorizing Apple Photos or adding a folder source.
- Next slice after that: simplify Apple Photos source entry so the `Add Source` flow becomes:
  - `Files or Folders…`
  - `Apple Photos…`
  and the Apple Photos path then handles `All Items`, albums, and `Custom Selection` inside one dedicated modal.

## Open Questions

- Is the current launch-time failure mainly a stale persisted source problem, a stale history replay problem, or source provisioning order during startup?
- Why are some beta builds apparently re-requesting Apple Photos authorization when a prior build was already authorized?
- When Apple Photos is already configured as an active source but permission is gone, should Hypnograph silently remove that source, show it as disabled, or explicitly repair it?
- Is the current denied-access failure mainly a stale saved source problem, a stale history replay problem, or both?
- Is the "Request Photos Access" action actually failing because the app is using the wrong re-request path, or because macOS does not allow the same kind of in-app re-prompt after denial and instead requires a Settings handoff?
- When Apple Photos is not yet authorized, should the Sources window still show Apple Photos as a source type, or only as an authorization action?
- Is the cleanest user flow:
  - choose `Apple Photos`
  - then choose `All Items`, an album, or `Custom Selection`
  - or does `All Items` deserve to remain a direct shortcut outside that modal?
- Does the existing album list already include `All Items` in the right place and shape, or does that still need cleanup?
- When Apple Photos permission is missing or denied, should previously saved Apple Photos sources be hidden, removed, or shown as disabled with an explicit repair action?
- Once the permissioning bug is fixed, how much of the remaining onboarding pain is truly the optimized-storage problem rather than this initial authorization failure?
