---
created: 2026-03-01
updated: 2026-03-01
status: proposed-spike
---

# Composition Timeline Pivot Spike

## Purpose

This is the canonical spike for the potential fundamental rewrite.

The core question is not "more UI reorganization" but this:
- how clip composition (inside a single clip)
- interacts with timeline sequencing (across many clips)
- without collapsing Hypnograph's core browsing/discovery feel.

This spike assumes AppKit windowization work is already in place and focuses on model/interaction decisions for timeline-first behavior.

## Why this is a fundamental rewrite

Timeline introduction changes the center of gravity of the app:
- clip history becomes timeline semantics
- transport behavior changes from browse/generate to editorial navigation
- clip composition and sequencing need one coherent contract
- render/export and playback must agree on the same timeline model

If this is not explicitly designed, we risk shipping a half-editor with ambiguous behavior.

## Reference Work

### 1) History-first model (completed)
- [20260115-unify-montage-sequence](../archive/20260115-unify-montage-sequence.md)
- Established clip-history tape as primary model.
- Key rule: sequence of clips, not sequence of sources.

### 2) Sequence/range rollback lessons (completed)
- [20260221-sets-reset-and-modeling-plan](../archive/20260221-sets-reset-and-modeling-plan.md)
- Key lesson: coupling sequence selection to history IDs created ambiguous behavior and complexity.

### 3) Recording/tape UX experiment (completed)
- [20260217-record-deck](../archive/20260217-record-deck.md)
- Valuable insight: "record performance" mental model is strong, but not equivalent to full timeline editing.

### 4) Layer editor direction (draft)
- [layer-editor](../active/layer-editor.md)
- Strong per-clip/layer interaction foundation, explicitly not yet a full NLE timeline.

### 5) Sets direction (active)
- [sets-model-direction](../active/sets-model-direction.md)
- Important warning: avoid set membership tied to history IDs.

### 6) Export as timeline expression (active planning)
- [export-clip-history-fcpxml](../active/export-clip-history-fcpxml.md)
- Already treats clip history as linear timeline segments with layered sources.

## The Core Design Tension

How much timeline power is enough?

Two failure modes:
1. under-build: timeline is shallow and confusing
2. over-build: app recenters into a conventional NLE and loses Hypnograph's identity

The spike should decide where the product intentionally sits.

## Fundamental Decisions To Make

1. **Primary Unit Of Editing**
- Current persistence already supports multi-clip sessions (`hypnograms` in `.hypno`).
- The decision here is operational semantics, not file-format capability:
  - Is the primary edited unit still direct `Hypnogram`/clip entries in session history?
  - Or do we introduce a distinct timeline item/entity that references clips with additional sequencing semantics?

2. **History vs Timeline Relationship**
- Is history a view of timeline?
- Is timeline a promoted/curated slice of history?
- Are they separate stores with explicit copy/add actions?

3. **Clip Mutation Semantics In Sequence**
- If editing clip X while parked in past context:
  - overwrite in place?
  - branch new revision?
  - append replacement at timeline head/tail?

4. **Generation Contract While On Timeline**
- At sequence end, should behavior be:
  - auto-generate next clip,
  - stop,
  - or mode-selectable?
- How does this coexist with watch mode and loop mode?

5. **Compound Clip Model**
- Do timeline items hold nested internal layer-timelines?
- Or is each timeline item always a flat `HypnogramClip` with source trims only?

6. **Playback Semantics**
- What does next/previous mean when timeline and history both exist?
- What is "current clip" identity when the same clip appears in multiple contexts?

7. **Transition Contract Across Boundaries**
- How clip-to-clip transitions should behave in timeline mode
- How boundary behavior should map to watch mode and manual navigation
- How transition behavior must match preview/live/export expectations

8. **Export Contract**
- Should preview/live/export share one timeline truth model?
- Which timeline semantics must be guaranteed render/export-stable in v1?

9. **Data/Migration Strategy**
- How existing history/recipe data migrates safely
- How old behavior is preserved for users not using timeline features yet

## Open Questions (Product + UX)

1. Does introducing a timeline become the central feature, or an optional advanced mode?
2. Is there a lightweight timeline pattern that avoids full NLE complexity while still being coherent?
3. Should timeline editing live in its own window, or in the play bar area with optional expansion?
4. What minimal timeline operations are non-negotiable for v1 (reorder, trim, duplicate, delete, split, ripple)?
5. How do we preserve "surprise and discovery" while adding deterministic sequencing controls?

## Spike Output Required

This spike is complete only when it produces:

1. A chosen model stance:
- history-first with timeline overlay
- timeline-first with history view
- dual-store model with explicit bridges

2. A v1 timeline feature envelope:
- exactly what operations ship
- explicitly what does not ship

3. A behavior contract:
- generation, navigation, edit semantics, and playback modes

4. A migration contract:
- how existing user data remains valid or is transformed

## Suggested Spike Method

1. Build a state-machine doc for `currentPosition`, `activeCollection`, and generation rules.
2. Write 8-12 scenario tests in plain language (user story + expected outcome).
3. Validate each scenario against:
- current behavior baseline
- proposed timeline behavior
- export implications
4. Decide v1 scope only after scenario pass.

## Candidate Scenario Set (to decide against)

1. Edit a clip while parked in past history, then hit next repeatedly.
2. Reorder two clips in timeline and toggle watch mode.
3. Add generated clips at timeline end while loop mode is on.
4. Compare transition behavior under timeline navigation vs watch mode.
5. Export selected timeline region and compare with playback expectation.
6. Remove a clip used in favorites/set contexts.
7. Duplicate a clip, alter layers, and verify identity semantics.
8. Transition across clips with different boundary-state history.

## Risks To Track

- Ambiguous contracts between browse mode and editorial mode
- Hidden coupling between boundary transitions and clip identity/state
- Migration complexity if identity semantics are changed mid-stream
- Scope creep toward full NLE without explicit product intent

## Related Projects (Execution Tracks)

- [sidebar-windowization](../active/sidebar-windowization.md)
- [sources-window](./sources-window.md)

These are enabling tracks. This spike defines the timeline/composition model they will eventually serve.
