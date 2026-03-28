---
doc-status: ready
---

# Volume Leveling (Phase 1 Reshape)

## Overview

Hypnograms pull audio from varied sources, so stepping through clips can cause abrupt loudness changes. This pass focuses on "good enough" consistency without introducing a full audio processing system.

Reduce clip-to-clip perceived loudness jumps in Preview with a minimal, reversible first pass. The likely first version is just one static loudness adjustment per clip plus a small amount of boundary smoothing, with the point being to make browsing feel less jarring before deciding whether deeper audio work is worth it.

## Rules

- MUST keep this as a minimal first pass rather than an audio-system redesign.
- SHOULD verify whether Preview and Render are actually using the same audio-mix path before trusting the result.
- SHOULD keep user volume controls unchanged; leveling should act as an additional multiplier layer rather than a replacement.
- MUST NOT turn this into a compressor, AGC pipeline, or other heavier dynamic-range processing pass.

## Plan

Start with one static loudness-match value per clip or hypnogram output, using conservative clamps so the fix cannot swing too far in either direction. If that helps but boundary changes still feel abrupt, add a short simple fade or ramp at clip transitions rather than introducing a more elaborate envelope system.

Validate this with quick manual listening across a mixed-loudness set in ordinary browsing and watch flow. If clip-to-clip jumps are noticeably reduced, transitions feel smoother, and playback behavior stays stable, the pass is good enough. If the benefit is weak, stop there and reassess rather than expanding scope.
