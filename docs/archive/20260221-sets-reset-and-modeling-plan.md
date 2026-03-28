---
doc-status: done
---

# Hypnograph Reset Plan: Sequence/Range Rollback

## Purpose

This document scopes the current project to reset only.

We moved quickly through multiple UX/model experiments in the last 48 hours:

- Record IN/OUT mental model
- Sequence selection on top of history
- Append vs replace load prompt for multi-clip sessions
- Watch vs loop behavior tied to sequence selection

The result is useful UX progress, but the core model now mixes concepts and creates ambiguous behavior. This document defines:

- What changed
- What we are intentionally rolling back now
- The exact executable rollback plan
- Reset guardrails and validation

Forward-looking Sets design continues in current queue-backed planning docs.

## What Changed Recently (Concrete)

Recent commits (2026-02-15):

- `0d439e4` Record deck HUD + recording/range workflow + `RecordingRenderPipeline`
- `fdedde2` Append vs replace prompt for multi-clip loads
- `13c1b45` Fix paused/still redraw regression
- `bdda800` Live mode feature flag
- `eae2ed3` Drag/drop reorder work
- `a9cc49b` Add-layer flow + stall backlog update

Major uncommitted additions after those commits include:

- Sequence-selection model coupled to history IDs (`sequenceClipIDs`)
- Sequence tab in left sidebar
- Sequence add/remove controls in player bar
- Sequence save/render menu actions and player controls actions
- Entry-point-specific load semantics (`allowReplacePrompt` split behavior)

## Why Reset Now

Primary concerns:

- Sequence currently references history clip IDs, so it is not an independent timeline model.
- Watch/loop behavior is spread across settings, player bar, and sequence membership checks.
- Save/load semantics differ by entry point (menu open vs list open).
- Current selection fallback behavior is surprising when no sequence is selected.
- The app has gained interaction complexity faster than we have stabilized the underlying contract.

Goal of reset:

- Return to a coherent baseline with history-only navigation and uniform load behavior.
- Preserve stable non-sequence improvements.
- Create a stable base before implementing Sets.

## Reset Scope

### Remove

- Sequence model logic and persistence coupling.
- Sequence UI surfaces (left tab and sequence-specific player controls).
- IN/OUT-era carryover and sequence-oriented aliases in current flow.
- Entry-point divergence for append/replace prompt logic.

### Keep

- Live mode feature flag and related stable plumbing.
- Paused/still effect redraw regression fix.
- Drag/drop source/layer improvements.
- Player bar general improvements that are not sequence-specific (if desired, can be kept with history-only buttons).
- Recording render pipeline code if it still serves simple current-clip rendering, otherwise leave dormant but compile-clean.

## Executable Rollback Plan (Commit-by-Commit)

### Commit 1: Core Model + Persistence Reset

Files:

- `Hypnograph/Dream/Dream.swift`
- `Hypnograph/ClipHistoryFile.swift`

Actions in `Dream.swift`:

- Remove `@Published sequenceClipIDs` and all related derived properties:
  - `sequenceSelectionCountText`
  - `sequenceTotalDurationText`
  - `hasSequenceSelection`
  - `isCurrentClipInSequence`
  - `sequenceEntries`
- Remove sequence helper methods:
  - `clipIndex(for:)` (if only used by sequence)
  - `advanceWithinSequence(direction:manual:)`
  - `selectedSequenceHypnograms()`
  - `recordingSession()` (if sequence-specific)
  - `sanitizeSequenceAgainstHistory()`
  - `toggleCurrentClipInSequence()`
  - `clearSequenceSelection()`
  - `removeSequenceClip(id:)`
  - `moveSequenceClips(fromOffsets:toOffset:)`
  - `moveSequenceClip(sourceID:targetID:)`
  - `selectSequenceClip(id:)`
- Remove sequence mutations from history flows:
  - `saveClipHistory(...)`
  - `restoreClipHistory()`
  - `replaceHistoryWithNewClip()`
  - `enforceHistoryLimit()`
  - `applyClipSelectionChanged(manual:)`
  - `appendLoadedHypnograms(_:)`
  - `replaceHistoryWithLoadedHypnograms(_:)`
- Remove sequence-based branching in playback:
  - `advanceOrGenerateOnClipEnded()`
  - `shouldAdvanceOnClipEndForCurrentMode()`
- Keep watch-mode behavior but make it history-only and explicit.

Actions in `ClipHistoryFile.swift`:

- Remove `sequenceClipIDs`.
- Remove legacy `inClipID` and `outClipID` migration path.
- Persist only:
  - `hypnograms`
  - `currentHypnogramIndex`
- Keep sanitize logic for history trimming/index clamping.

Validation:

- Build succeeds.
- App launch restores history correctly.
- Next/previous/new/delete/clear history all work.

### Commit 2: UI Surface Reset

Files:

- `Hypnograph/Views/LeftSidebarView.swift`
- `Hypnograph/Views/ContentView.swift`
- `Hypnograph/Views/Components/PlayerControlsBar.swift`
- `Hypnograph/AppCommands.swift`

Actions:

- Remove left sidebar Sequence tab and all sequence row/reorder UI.
- Remove sequence add/remove button and sequence count indicator from player controls.
- Keep player controls focused on transport/watch/save/render current clip.
- Remove sequence menu actions:
  - Add/remove current clip from sequence
  - Clear sequence
  - Save Sequence / Save & Render Sequence
- Rename player strings if needed so they describe current-clip behavior only.

Validation:

- No sequence labels/buttons/tabs remain.
- Player controls remain clean and functional.
- Command menu has no sequence actions.

### Commit 3: Load Semantics Re-Unification

Files:

- `Hypnograph/Dream/Dream.swift`
- `Hypnograph/Views/ContentView.swift`
- Any other load entry point that passes `allowReplacePrompt`

Actions:

- Remove `allowReplacePrompt` parameter and branching.
- Use one uniform load behavior at all entry points for now.
- Recommended temporary baseline during reset:
  - Always append loaded session clips to history.
- Keep append-vs-replace UX idea documented for later reintroduction under Sets (not active in code now).

Validation:

- Open from file and open from list follow identical behavior.
- Multi-clip loads are predictable and do not touch sequence state.

### Commit 4 (Optional): Lightweight Doc Sync

Files:

- `docs/hypnograph/archive/20260217-record-deck.md`
- `docs/hypnograph/roadmap.md`

Actions:

- Mark sequence/range experiments as rolled back.
- Keep a pointer to Sets direction doc.

## Guardrails During Rollback

- Do not alter stable rendering/effects plumbing unrelated to sequence/range.
- Keep commits small and reviewable.
- After each commit run build + quick manual smoke test.
- If any behavior ambiguity appears, prefer history-only deterministic behavior.
- Keep forward-looking Sets modeling out of this reset implementation.

## Next-Chat Starting Checklist

Use this to resume in a fresh context window:

- Step 1: Execute rollback commits 1-3 exactly in order.
- Step 2: Confirm smoke test matrix:
  - playback
  - watch toggle
  - save current
  - render current
  - load session
- Step 3: Confirm reset checkpoint commit before any new model work.
- Step 4: Continue Sets planning in the current queue-backed planning docs.
