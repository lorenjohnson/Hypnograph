# Add Global Source Framing Setting: Overview

**Created**: 2025-01-16  
**Status**: Proposal / Planning

Goal: add a single global **Source Framing** setting that controls how each source/layer is mapped into the output frame: **Fill** (crop) vs **Fit** (no crop).

This explicitly separates two different concepts:

- **Output Aspect Ratio** (existing): the aspect ratio of the output frame (e.g. `16:9`, `9:16`, `Fill Window`).
- **Source Framing** (new): how each source fits into that output frame (`Fill` vs `Fit`), always preserving source aspect ratio (no stretching).

## What it means

Output Aspect Ratio answers: “What is the shape of the frame we’re composing into?”

Source Framing answers: “For each source placed into that frame, do we crop it (Fill) or show it entirely (Fit)?”

Important behavior:
- Any “blank”/unused area created by **Fit** must be **transparent** so lower layers show through in a layered montage.

## Naming (product + code)

Recommended user-facing name:
- **Source Framing**: `Fill` / `Fit`

Recommended code name:
- `sourceFraming: SourceFraming` where `SourceFraming` is an enum: `.fill`, `.fit`

## Non-goals (explicitly out of scope)

- Per-source/per-layer overrides
- New aspect ratio presets or additional framing modes.
- Any additional “window fit/fill” setting for preview beyond the existing Output Aspect Ratio choices.
