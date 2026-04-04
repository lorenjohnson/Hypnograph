---
doc-status: done
---

# Apple Photos Permissioning and Source Entry

## Overview

This project restored trust in the Apple Photos path across permission recovery, source entry, and download-time waiting behavior.

The main outcome is that Hypnograph now behaves much more coherently when Apple Photos access is missing, denied, restored, or slow because assets are still downloading. Instead of appearing broken, the app now steers the user toward the right recovery path, avoids silently keeping unusable Apple Photos sources alive, and surfaces loading state in a quieter way when PhotoKit-backed downloads are in progress.

The work also simplified the Apple Photos source-entry experience so that `Apple Photos…` now leads into one unified chooser for `All Items`, `Specific Albums`, or `Custom Selection`, and removed the lingering automatic `All Items` default behavior when Photos access merely happens to exist.

Separate but related cleanup also improved the failure path for missing filesystem sources. When all sources for a composition are unavailable, the app now shows a dedicated unavailable-sources state instead of just sitting on black, and missing source folders are reflected live in the Sources panel.

## Rules

- MUST keep Apple Photos permission recovery explicit and understandable.
- MUST avoid silently treating unauthorized Apple Photos sources as usable.
- MUST keep denied-access recovery grounded in System Settings rather than pretending the app can always re-prompt.
- MUST make Apple Photos source entry coherent enough that `All Items`, albums, and `Custom Selection` are chosen through one obvious path.
- MUST surface PhotoKit-backed download waiting state without overwhelming the main composition view.
- SHOULD keep debug-only harness and reset behavior available for repeated local testing without polluting release behavior.
- SHOULD keep missing-source failure states explicit instead of letting the app appear frozen or broken.

## Scope

- Completed:
  - clarified first-launch and denied-access Apple Photos recovery messaging
  - moved denied-access guidance into the contexts where it is actually actionable
  - unified Apple Photos source entry under one modal flow
  - removed automatic `Apple Photos: All Items` source selection
  - cleaned up unauthorized Apple Photos sources when access is definitively gone
  - added PhotoKit progress-driven download indication for Apple Photos-backed media
  - simplified download UX into a compact native macOS progress indicator
  - guarded repeated end-of-history generation during in-flight Apple Photos downloads
  - improved missing local source handling in Sources and in the main composition area
- Explicitly not solved here:
  - signed beta distribution and persistent Apple Photos authorization across unsigned builds
  - richer partial-failure UX for compositions where only some layers are broken
  - general slow-loading support for non-PhotoKit mounted cloud volumes

## Plan

- This project is complete enough to archive.
- The biggest remaining follow-on questions belong in separate work:
  - signed Apple Developer distribution and release readiness
  - partial source-failure presentation for mixed-validity compositions
  - broader slow-loading handling for non-Photos external filesystems

## Open Questions

- Should partially broken compositions eventually render with richer per-layer failure affordances rather than today’s minimal warning/icon treatment?
- Should the loading indicator remain purely unobtrusive, or eventually gate more of the composition UI when the current target is still unresolved?
- When the app is distributed as a properly signed beta, which of the previously observed Apple Photos re-authorization behaviors disappear entirely?
