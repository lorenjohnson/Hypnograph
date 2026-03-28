---
doc-status: ready
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
