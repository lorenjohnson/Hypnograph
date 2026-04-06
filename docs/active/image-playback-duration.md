---
doc-status: draft
---

# Image Playback Duration

## Overview

This project is about giving image-only layers a real playback model instead of letting them fall through video-oriented behavior that does not fit. Right now, when a composition or layer is built from still images only, playback duration can become undefined, image rendering can behave inconsistently, and the app may fail to advance because there is no clear concept of how long an image should remain on screen.

The likely direction is to treat image playback length as its own explicit piece of state, separate from video in/out trimming. That would allow image-only layers to render predictably, participate in timeline UI in a meaningful way, and still respect composition-length constraints and random generation behavior without pretending they are videos.

This project is not just about fixing one hang or one missing thumbnail. It is about making still images first-class timed media inside the playback model.

## Rules

- MUST define a clear duration model for image-only layers instead of relying on implicit or effectively infinite playback.
- MUST make image-only compositions advance correctly once their playback duration is complete.
- MUST preserve mixed-media support, so images and videos can still coexist in the same composition model.
- MUST treat image playback length as separate from video in/out points.
- SHOULD provide timeline behavior for image-only layers that still feels legible, even if it differs from video trimming UI.
- SHOULD make random image selection respect both image playback duration and the existing new-composition length constraints.
- MUST NOT solve this by simply degrading image support or treating still images as a second-class source type.

## Plan

- Smallest meaningful next slice: trace how image-only layers currently derive duration, rendering, and advancement behavior, and identify where the playback model assumes video semantics.
- Immediate acceptance check: there is a clear, implementable model for how long an image-only layer plays and when an image-only composition should advance.
- Follow-on slice: add explicit playback length for image-only layers and make image-only compositions render and advance reliably.
- Later slice: improve timeline presentation for image-only layers so the UI reflects the new duration model clearly.

## Open Questions

- Does this project reopen the question of combining the timeline thumbnail view attached to the play bar with the composition and layer timeline view inside the Composition window?
- Should image playback length live per layer, per selected source item, or both?
- What is the simplest useful timeline representation for an image-only layer: one thumbnail with a duration control, or something richer?
- How should random image selection map onto the configured composition-length range when no video duration exists to trim against?
- Are there any existing playback or thumbnail assumptions elsewhere in the app that break once still images become explicitly timed media?
