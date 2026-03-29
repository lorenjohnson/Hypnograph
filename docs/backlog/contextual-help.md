---
doc-status: draft
---

# Contextual Help

## Overview

This project explores a stable in-app place for contextual help text that explains controls as the operator moves through the interface. The reference pattern is closer to Ableton Live's help-view behavior, where hovering a control surfaces a brief explanation in a dedicated part of the screen instead of forcing the operator to guess or leave the flow to look something up.

This is separate from simply removing the old clean-screen instructional HUD message. That cleanup belongs in the active panel work. The real project here is to decide whether Hypnograph wants a durable contextual-help surface, where it should live, and which interaction pattern makes the most sense for a live-use visual instrument.

The likely value is twofold: faster learning of controls and a clearer place for keystroke or interaction hints when they are useful. The harder part is making that guidance present enough to help without making the app feel noisier or more instructional than it wants to be during actual composition or performance.

## Rules

- MUST treat this as a separate project from removing or disabling the existing clean-screen HUD message.
- MUST identify a stable screen location or UI surface for contextual control help.
- SHOULD study hover or rollover help behavior similar to Ableton Live without assuming Hypnograph needs the exact same presentation.
- SHOULD account for both control-description help and possible keystroke or hotkey guidance where useful.
- MUST preserve live usability and avoid turning the app into a constantly chatty instructional interface.
- MAY support conditional or temporary visibility if that produces a better balance than always-on help.
- MUST coordinate with [studio-panels-cleanup.md](/Users/lorenjohnson/dev/Hypnograph/docs/active/studio-panels-cleanup.md) only where the old HUD surface overlaps visually.

## Plan

- Smallest meaningful next slice: identify likely candidate surfaces for contextual help in the current UI and compare their tradeoffs.
- Immediate acceptance check: the project should leave behind a clear recommendation for where help text belongs and what interaction pattern should trigger it.
- Follow-on slice: prototype one narrow version of contextual help on a few representative controls and test whether it feels useful or distracting.

## Open Questions

- Should contextual help appear on hover only, focus only, selection changes, or some combination?
- Is the best home for help text a corner overlay, a dedicated panel region, or an existing status area?
- Should keystroke guidance and control-description help be the same system or adjacent but separate systems?
- How visible should the help surface be during active composition versus first-run exploration?
