doc-status: done
---

# Sources Window

## Overview

`Sources` is now being implemented as a dedicated Studio window so source management stops living primarily in menus.

The first important shift is structural: the window now lives in the same Studio window system as the other panels. The second is model-level: source libraries are now treated as distinct file-and-folder source sets that can be enabled, disabled, and removed honestly instead of being silently collapsed into one bucket.

## Rules

- MUST keep `Sources` as a dedicated Studio window.
- MUST support media-type filtering, file-and-folder source management, and Apple Photos scope management.
- MUST make source libraries real independent libraries.
- SHOULD let this window replace the old `Sources` menu rather than duplicate it long-term.

## Plan

This pass is complete enough to stop here. `Sources` now works as a dedicated Studio window, file-and-folder source sets are real libraries, Apple Photos management is usable in place, and the old `Sources` menu is gone.

Likely later refinements, but not part of this completed pass:
- revisit whether composition-specific file import needs to come back somewhere later, but not in this window for now
- keep tuning the exact feel of Apple Photos interactions if runtime use keeps surfacing friction
- decide later whether the window deserves its own shortcut or additional menu cleanup

## Review Notes

- The old `Sources` command menu is being retired in favor of this window.
- `Pick Custom Photos` moved out of `Quick Actions`; the current direction is a lightweight affordance inside the Apple Photos section instead.
- The current source-library add action now wants to represent `File & Folder Sources` rather than only folders.
