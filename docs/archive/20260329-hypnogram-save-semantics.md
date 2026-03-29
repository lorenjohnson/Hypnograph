---
doc-status: done
---

# Save Semantics for Hypnogram Files

## Overview

This project is about making save behavior feel like a normal document app again. Right now repeated `Save` tends to produce new uniquely named files, which makes the basic model feel off.

The expected behavior is simpler: `Save` should overwrite the current file target for the working hypnogram or session, and `Save As` should choose a new file target and then make that the active save target from then on.

There may already be enough internal identity in the model, such as UUID-based tracking, to support this cleanly. But the important thing for this project is to define file-target ownership and working-file semantics explicitly so the user-facing behavior is predictable.

## Rules

- MUST make `Save` behave like ordinary document overwrite of the current file target.
- MUST make `Save As` choose a new file target and then treat that new path as the active save target.
- SHOULD preserve a clear notion of working identity for the currently open hypnogram or session.
- MUST NOT keep generating new uniquely named files on repeated ordinary `Save`.

## Plan

First define the user-visible save contract in plain language: what counts as the currently open working file, when that target changes, and how `Save` versus `Save As` behave after a file has already been written once. Then confirm whether the current internal identity model already supports that contract or whether file-target tracking needs to be made more explicit.

## Completion Notes

This pass is complete enough to stop here.

Implemented behavior:
- `Save` overwrites the current file target when the selected Composition already has one.
- `Save` creates a new hypnogram file automatically when the selected Composition does not yet have a file target.
- `Save As` writes to a chosen path and then makes that path the active save target for the selected Composition.
- repeated `Save` no longer creates duplicate files or duplicate hypnogram-store entries for the same file path.
- loading a single-composition hypnogram file now carries its file target forward into Studio, so edits to that loaded Composition save back to the same path.
- opening a hypnogram file now also switches playback-end behavior to loop the loaded Composition, so a short opened file will not immediately auto-advance away.

## Open Questions

- whether multi-hypnogram files should eventually gain their own distinct save contract instead of flowing through the single-hypnogram save path
