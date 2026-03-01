---
created: 2026-03-01
updated: 2026-03-01
status: proposed-spike
---

# Effects Chain Composition Spike

## Purpose

Define the model and terminology for effects and effect chains without coupling it to timeline-pivot decisions.

This spike exists to answer one core product/model question cleanly:
- how "effect" and "effect chain" should be represented, authored, named, and consumed.

## Why this is separate

- Timeline/composition pivot has its own hard model questions.
- Effects-chain flattening and naming has its own hard model questions.
- Mixing both in one spike creates ambiguity and slows decisions.

## Current Working Assumption

- The practical concept users already understand is `effect chain`.
- Any flattening/unification should be framed as clarifying and simplifying effect-chain behavior, not inventing disconnected new jargon.

## Inputs To Reconcile

- Existing right-side effects behavior and chain workflows in main app.
- Effects Studio runtime-authoring workflows.
- Library/template behavior and chain application semantics.
- Existing roadmap issues around chain selection, mutation confusion, and chain usability.

## Fundamental Decisions To Make

1. **Canonical Entity**
- Is `effect chain` the single canonical entity in user-facing model?
- If yes, how are single effects represented (one-step chains vs separate type)?

2. **Terminology**
- What terms are used in UI and docs (`effect`, `effect chain`, `template`, `preset`)?
- Which terms are internal-only vs user-facing?

3. **Editing Semantics**
- What does "apply chain" do (copy vs reference)?
- What does "edit applied chain" mutate (instance vs library template)?
- How is "save as new" vs "update existing" resolved?

4. **Nesting/Composition Rules**
- Can one chain include another chain?
- If yes, what are cycle and depth rules?
- How are nested parameters exposed or hidden?

5. **Library and Identity**
- How are chains identified/versioned?
- How are bundled chains vs user chains handled?
- What happens when a referenced chain changes?

6. **Main App vs Effects Studio Responsibility**
- What chain editing belongs in main app?
- What deeper authoring belongs in Effects Studio?

## Spike Output Required

1. A clear model contract for effects/effect-chains.
2. A terminology contract for docs + UI.
3. An edit/apply/save behavior contract (copy/reference/update semantics).
4. A migration/backward-compatibility note for existing chains.

## Suggested Spike Method

1. Enumerate current user-facing chain actions and expected results.
2. Write scenario tests for apply/edit/save/update/duplicate/nest cases.
3. Resolve ambiguous behaviors into one consistent contract.
4. Produce naming table for UI labels and model terms.

## Candidate Scenario Set

1. Apply a library chain to a clip, then edit it locally.
2. Update a library chain and verify existing clips behavior.
3. Save a modified chain as new and reapply in another clip.
4. Duplicate a chain and compare identity/version semantics.
5. Include chain B inside chain A (if allowed) and edit B.
6. Move between main app and Effects Studio while preserving chain behavior.

## Risks To Track

- Hidden copy/reference confusion for users
- Breaking existing recipe expectations during migration
- Overloading main app with authoring depth that should remain in Effects Studio

## Related Projects

- [composition-timeline-pivot-spike](./composition-timeline-pivot-spike.md)
- [sidebar-windowization](../active/sidebar-windowization.md)
