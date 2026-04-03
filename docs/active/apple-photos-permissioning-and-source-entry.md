---
doc-status: in-progress
---

# Apple Photos Permissioning and Source Entry

## Overview

This project is about restoring trust in the Apple Photos first-run path before treating optimized storage as the main problem.

Right now the more immediate failure appears to be that on a fresh build or first fresh run, Hypnograph can ask for Apple Photos permission, receive it, and still fail to behave as though Apple Photos is actually available. That makes the onboarding feel broken at the exact moment when the app is supposed to become magical.

The active focus here is therefore narrower than the broader optimized-storage spike:

1. Apple Photos permissioning must become predictable and reliable on first grant.
2. If Apple Photos is not yet authorized, denied, or canceled, the Sources window must make the next step obvious and recoverable.
3. Adding Apple Photos as a source should have a clearer entry flow, with `All Items` and albums treated as source choices inside one coherent picker rather than as separate conceptual paths.

The wider concerns around optimized storage, slow cloud-backed loading, and local disk usage are still real. They remain on the map as background context, but they are not the first thing to solve in this project because the current permissioning bug is likely obscuring the actual user experience underneath.

Current concrete failure modes already observed:

- If the user rejects Apple Photos permission at first launch, the app can still appear to retain `Apple Photos All Items` as an active source.
- In that state, Hypnograph can continue trying to render Apple Photos-backed content and simply appear broken or blank instead of failing clearly.
- The Sources window does show a way to request Apple Photos permission again, but that action does not currently behave reliably.
- At least part of the bad state may be compounded by reopening onto a previous history item whose sources depended on earlier Apple Photos access.
- After some interaction inside the same session, the app can eventually settle into a more correct no-sources state, where trying to generate a new composition simply shows the no-media-sources screen again.
- That makes the likely critical bug narrower: the initial permissioning and first-load transition appears to be wrong, while the later steady-state behavior may already be closer to correct.

## Rules

- MUST treat Apple Photos permissioning and first-use source entry as the current implementation focus.
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

- MUST verify what happens on first launch when Apple Photos permission is:
  - granted
  - denied
  - canceled
- MUST make the Sources window able to surface Apple Photos authorization as an obvious next action when permission is missing.
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

- Smallest meaningful next slice: reproduce and trace the current Apple Photos permission flow on a fresh run, especially the first-grant path, and identify where the app still behaves as though Photos access is unavailable.
- Smallest meaningful next slice: reproduce and trace the current Apple Photos permission flow on a fresh run, especially the initial denied or granted path, and identify where startup or first-load state is assuming Apple Photos access before authorization state has settled.
- Smallest meaningful next slice: make debug runs easier to reset and inspect so the first-launch permission path can be exercised repeatedly without touching the normal app-support directory.
- Smallest meaningful next slice: provide a lightweight debug reset path for clearing Apple Photos permission and the debug app-support directory without adding more launch-time lifecycle interference than necessary.
- Immediate acceptance check: after granting Apple Photos access, Hypnograph reliably recognizes that access without requiring unrelated UI actions or relaunch-like behavior, and after denying access it does not continue behaving as though `All Items` is still active.
- Follow-on slice: make the no-permission and denied/canceled states in Sources clearly actionable, including a way to authorize Apple Photos from there that actually works.
- Next slice after that: tighten the Apple Photos source-entry flow so `All Items`, albums, and `Custom Selection` all live under one coherent Apple Photos modal instead of the current split menu structure.

## Open Questions

- Is the current first-grant failure mainly a race condition, stale authorization state, or source provisioning order problem?
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
