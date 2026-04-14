---
doc-status: draft
---

# Layout Transforms vs Viewer Pan/Zoom

## Overview

This is a feature-design spike about two related but importantly different kinds of interaction: editing the composition itself, and temporarily navigating the rendered view during playback.

Hypnograph likely needs both. On the composition side, layers should eventually support layout transforms such as position, scale, crop, and zoom, and those changes should persist as part of the authored hypnogram. On the viewer side, playback should also support temporary pan and zoom of the currently rendered image, including while paused, with a quick way to reset back to normal framing.

The core issue is that these can look similar at the interaction level while meaning very different things in the model. A drag or zoom gesture might either be mutating a layer's layout or simply navigating the viewer for inspection. If that boundary is not explicit, the app will feel confusing and error-prone very quickly.

So this spike should not just list wanted features. It should determine the behavioral boundary between authored transforms and temporary viewer navigation, and especially whether composition editing needs an explicit edit mode or similar guardrail so playback interactions are not mistaken for layout edits.

## Rules

- MUST keep composition-editing transforms distinct from playback-time viewer navigation.
- MUST define which interactions persist into the hypnogram and which are temporary viewer-only state.
- SHOULD prefer an interaction model that makes accidental edits unlikely.
- SHOULD consider an explicit transform-edit mode if that is the clearest way to separate authoring from viewing.
- MUST include a quick reset path for viewer pan/zoom if that capability ships.

## Plan

First define the two models in plain language. Composition transforms are authored per-layer operations such as position, scale, crop, and zoom, and they should persist with the composition. Viewer pan/zoom is temporary viewport navigation of the rendered hypnogram and should not mutate the composition.

Then decide how the app should signal and protect that boundary in practice. The main question is whether normal playback should remain a safe viewing mode while transform editing happens only inside an explicit editing state, tool, or surface. Once that is clear, the next implementation slice can define the initial control set for each side and choose the simplest interaction design that keeps the model legible.
