---
doc-status: archived
---

# Play Rate vs History Playback Speed

## Overview

This backlog question was resolved as a "don't do" cleanup rather than a larger product project.

The user-facing history playback speed control had already been removed, but the underlying implementation path was still present in code and could still influence playback behavior through hidden persisted state. That meant the old overlap remained internally even though it no longer existed in the UI.

The project outcome was to remove that hidden history-speed path and simplify playback back down to the composition's own play-rate controls.

## Result

- Removed the hidden `timelinePlaybackRate` / `historyPlaybackRate` implementation path.
- Simplified playback so video rate and still-image timing come only from the composition-level play-rate model.
- Left any future layer-level rate work as a separate question rather than carrying forward the old history-speed model.
