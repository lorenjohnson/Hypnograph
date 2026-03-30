---
doc-status: in-progress
---

# Panel Control Family Standardization

## Overview

This project standardizes the slider and toggle control family used across Studio panels. Right now the app mixes custom AppKit-backed range controls with default SwiftUI sliders and toggles, which creates both visual inconsistency and interaction inconsistency inside the same windows.

The immediate direction is to standardize toward AppKit-backed controls for panel UI. The first implementation slice should use the `New Compositions` window as the proving ground, replacing the current SwiftUI frequency sliders and default toggles with controls that match the thinner track, circular handle, inset layout, and more reliable interaction model already used by the AppKit-backed range sliders.

This project also needs to account for the richer slider cases already present elsewhere in the app, including stepped sliders and sliders with snap-point legends. The first pass does not need to solve every slider variant, but it should establish the shared control family that later passes can extend.

## Rules

- MUST standardize toward AppKit-backed sliders and toggles for Studio panel controls.
- MUST treat the `New Compositions` window as the first implementation slice and visual reference point.
- MUST preserve or improve interaction reliability inside floating panels, especially around drag handling.
- SHOULD keep the visual language aligned with the existing AppKit-backed range sliders: thinner tracks, circular handles, and consistent insets.
- SHOULD make the single-value slider extensible enough to support later variants such as stepped snapping and visible snap-point markers.
- MUST NOT attempt to replace every existing slider in one pass before the shared control family is proven in one focused window.

## Plan

- Smallest meaningful next slice: create AppKit-backed single-value slider and toggle controls that visually match the range slider family, then apply them to the `New Compositions` frequency and randomization controls.
- Immediate acceptance check: the `New Compositions` window should feel visually consistent across range sliders, frequency sliders, and toggles, and the new controls should behave reliably in the panel.
- Follow-on slice: if the first pass feels right, extend the shared slider family to other panel surfaces such as `Composition`, `Output Settings`, and other settings windows, including support for snap-point variants where needed.

## Open Questions

- Should the AppKit toggle mimic the current switch appearance exactly, or shift toward a simpler panel-native look that better matches the slider family?
- Is it better to build snap-point and legend support directly into the first shared slider control, or add that as a second pass once the base single-value slider is proven?
