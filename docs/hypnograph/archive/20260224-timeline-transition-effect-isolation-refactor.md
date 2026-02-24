---
status: completed
created: 2026-02-24
completed: 2026-02-24
owner: codex
---

# Timeline Transition Effect Isolation Refactor

## Objective

Refactor playback transition architecture so clip-to-clip transitions are visually correct and isolated:

- Outgoing clip keeps rendering with outgoing clip effect state until it is fully faded out.
- Incoming clip renders with incoming clip effect state from the start of fade-in.
- No effect-state bleed between clips during overlap.

Secondary objective:

- Reduce overall complexity where practical.
- Avoid unnecessary line-count growth; any growth must be justified by architecture clarity/correctness.

## Scope

In scope:

- Dream preview/live transition playback architecture.
- HypnoCore rendering/effect plumbing needed to support effect context isolation.
- Keep current UX/behavior stable except fixing transition bleed.

Out of scope for this pass:

- Full timeline composition UI.
- Export timeline parity with cross-clip transitions.
- Buffer-capacity guardrails optimization (deferred final phase, optional).
- Divine compatibility work (allowed to break if required by core correctness).

## Non-Negotiable Requirement

Smooth transition without effect bleed is required:

- Clip A keeps Clip A look to invisibility.
- Clip B fades in with Clip B look immediately.

## Constraints

- Do not delete or modify `website/` (untracked WIP).
- Keep existing playback-speed/chevron work unless directly incompatible with this refactor.
- No commits in this work session.

## Plan

### Phase 1: Baseline + Mapping

- Confirm current transition/effect coupling points.
- Identify minimum set of APIs/classes to refactor.
- Keep change surface tight.

### Phase 2: Core Refactor (HypnoCore-first)

- Introduce explicit, isolated effect-context behavior for transition playback.
- Ensure outgoing/incoming clip render instructions no longer depend on shared mutable clip state.
- Keep design reusable for future timeline engine evolution.

### Phase 3: Dream Integration

- Wire preview/live playback to use refactored context model.
- Preserve current controls and transport behavior.
- Preserve fast-play/reverse work already in branch.

### Phase 4: Complexity Pass

- Remove obsolete glue/duplication created by old behavior.
- Keep resulting code easier to reason about than before.

### Phase 5: Verification

- Build `Hypnograph` and verify transition behavior.
- Build `Divine` as informational check only (do not block on fixing if broken).
- Record outcomes and follow-ups.

### Phase 6 (Deferred / Optional): Buffer Capacity Guardrails

- Explicitly postponed until app is runnable/stable on the new architecture.
- If needed, add as a separate optimization pass informed by observed memory behavior.

## Execution Notes

### 2026-02-24

- Project doc created.
- Scope confirmed with user:
  - proceed with full refactor now,
  - prioritize architectural correctness and reduced complexity,
  - defer buffer guardrails to final optional phase.

### 2026-02-24 (implementation)

- Implemented transition effect-context isolation in HypnoCore and Dream playback.
- Added `EffectManager.makeTransitionSnapshotManager(...)` to create a frozen manager for outgoing clips during overlaps.
- Added `FrameBuffer.cloneState()` to preserve temporal history for outgoing transition playback.
- Added `RenderEngine.rebindEffectManager(_:on:)` so app code can rebind player-item instructions without referencing internal render types.
- Updated `PlayerContentView` to:
  - retain per-slot effect managers strongly (instructions store weak refs),
  - rebind incoming items to explicit managers,
  - freeze currently visible slot effects before transition,
  - clear slot manager refs when outgoing items are torn down.
- Updated `PreviewPlayerView` and `LivePlayer` to:
  - freeze outgoing clip with snapshot manager before building incoming clip,
  - bind incoming player items to the primary manager,
  - track last rendered clip snapshot for correct freeze semantics.

### 2026-02-24 (verification)

- `xcodebuild -project Hypnograph.xcodeproj -scheme Hypnograph -configuration Debug -sdk macosx build` succeeds.
- Informational compatibility check:
  `xcodebuild -project Hypnograph.xcodeproj -scheme Divine -configuration Debug -sdk macosx build` succeeds.
- `xcodebuild -project Hypnograph.xcodeproj -scheme HypnoCoreTests -configuration Debug -sdk macosx test` succeeds (9 tests passed).
- No dedicated runtime visual QA completed yet for transition bleed elimination; manual playback validation still required.

### Deferred

- Buffer-capacity guardrails remain deferred by design for a follow-up optimization pass after runtime validation.

### 2026-02-24 (post-implementation cleanup)

- Removed dead coordinator fields in preview playback (`containerView`, `currentPlayerItem`) to reduce state surface.
- Extracted shared slot helpers in `PlayerContentView` (`source(for:)`, `clearSlot(_:)`) to remove repeated teardown logic.
- Extracted `freezeOutgoingEffectsIfNeeded(...)` helper in `PreviewPlayerView` to reduce branching duplication.
- Re-ran build/test verification after cleanup:
  - `Hypnograph` build succeeds.
  - `HypnoCoreTests` succeed (9 tests passed).
