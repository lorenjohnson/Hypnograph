---
doc-status: ready
---

# Sequences Plan

## Plan

1. Verify the current baseline behavior precisely.
   - Confirm what happens when the operator is parked mid-history and presses `Play` with loop mode off.
   - Confirm what happens when the operator presses `New` from mid-history.
   - Confirm which prior clip is currently used for carry-forward behavior such as previous effect or other inherited state.
2. Abstract the shared timeline-strip control first.
   - Settle on a working name for the control and treat it as one reusable UI component rather than a one-off implementation at each level.
   - Make it capable of driving the current global, layer, and new history-level cases from different data sources with the same visual and interaction model.
   - Use this as a quality-improvement point for all places that already use the same basic timeline-strip idea.
3. Prototype the history timeline strip above the play bar.
   - Use the same visual family as the current global or layer timeline strips.
   - Plumb the shared control into a history-level instance that shows whole hypnograms across history as thumbnail segments.
   - Make the surface showable and hideable rather than permanently expanded.
   - Design that show or hide behavior alongside the existing hypnogram timeline so those controls do not diverge unnecessarily.
4. Use that strip as the first sequence-selection surface.
   - Add in and out handles that snap to whole-hypnogram boundaries.
   - Let the strip make current position, live end, and selected range more obvious than the current history controls do.
   - Keep this focused on whole-hypnogram selection rather than arbitrary timeline editing.
5. Decide the semantics of `New` from mid-history.
   - Preferred direction to test: insert at the current position so authored flow can branch naturally from where the operator is working.
   - If insertion creates too much model or persistence complexity, fallback direction: continue appending at the end, but derive carry-forward behavior from the currently viewed hypnogram rather than from the latest clip at the tail.
6. Decide the semantics of `Play` from mid-history when loop mode is off.
   - Test whether the better default is to continue into newly generated flow rather than simply walking forward through older history.
   - If needed, treat this as a configurable behavior or mode, but only if the simpler default is not sufficient.
7. Turn the first validated direction into implementation slices.
   - history strip UI and show or hide behavior
   - coordinated show or hide UX for history and hypnogram timeline surfaces
   - shared timeline-strip control cleanup and reuse
   - range-selection semantics
   - mid-history `New` behavior
   - save or export of selected range

Scenarios:
- The operator is on history item 5 of 10, presses `Play`, and expects a sensible return into live generation rather than an accidental walk through stale history.
- The operator is on history item 5 of 10, presses `New`, and expects the new hypnogram to be based on item 5 rather than item 10.
- The operator marks an authored range across multiple history items using the history strip and expects those boundaries to snap to whole hypnograms.
- The operator saves or exports a selected range and expects the result to follow the same range semantics shown in the strip.
- The operator hides the history strip and ordinary watching still feels simple and lightweight.
