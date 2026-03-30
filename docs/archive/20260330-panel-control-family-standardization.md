---
doc-status: completed
---

# Panel Control Family Standardization

## Overview

This project standardized the slider and toggle control family used across Studio panels. The app had been mixing custom AppKit-backed range controls with default SwiftUI sliders and toggles, which created both visual inconsistency and interaction inconsistency inside the same windows.

The project established a shared AppKit-backed single-value slider and toggle family, first proving it in `New Compositions` and then extending it across the major Studio panel surfaces. It also included a small follow-on pass for stepped slider snap markers so the shared control family could cover the most important snapping cases without reverting to custom one-off slider implementations.

This project is now complete enough to archive. The shared control family is in place, the major panel/window surfaces are using it, and the remaining design work belongs more to ongoing panel polish than to the standardization project itself.

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
