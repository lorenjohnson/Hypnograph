---
created: 2026-03-01
updated: 2026-03-01
status: proposed-spike
---

# Effects Engine Pass Graph Pivot Spike

## Purpose

Decide whether Hypnograph should pivot from the current linear effects-chain runtime to a pass-graph effects engine as the long-term default.

This spike answers one core product/architecture question:
- what effects model best supports Hypnograph's identity and visual goals over the next major phase.

## Why This Spike Exists Now

- Current effects are strong and expressive, but often land too "digital" versus the analog signal character we keep targeting.
- Many convincing analog-style references are built as explicit multi-pass pipelines, not single-pass or simple linear chains.
- The translation gap from external reference effects into our current model is now a recurring product constraint, not a one-off annoyance.
- We need clarity on the definitive direction before investing in another round of incremental effects work.

## Trigger References

Primary external trigger work:
- RetroArch `slang-shaders` ecosystem/spec (multi-pass analog simulation patterns from game-video shader pipelines).
- Retro-inspired shader experiments reviewed during current exploration phase (including `RetroTVFX` reference work and related ports/tests).

Internal reference context:
- Current effects architecture: `docs/architecture/effects.md`
- Current effects-chain model spike: `docs/backlog/effects-chain-composition-spike.md`

## Current Working Assumption

- Hypnograph will likely move to a pass-graph-first engine as the definitive effects runtime.
- OFX is a possible compatibility/adapter direction, not the core runtime model.
- The current system is a stepping stone and may be replaced rather than extended indefinitely.

## Scope Of This Spike

In scope:
- Define the target runtime model (pass graph) at product and system-contract level.
- Define transition stance from current effects runtime to the new runtime.
- Define the strategic path for Effects Studio under the new direction.
- Define interoperability posture (including whether/when OFX matters).

Out of scope:
- Timeline/composition model redesign (covered by composition timeline spike work).
- Final authoring UI design details.
- Immediate implementation or migration execution.
- Full OFX implementation commitment.

## What This Spike Must Decide

1. **Direction**
- Is pass-graph the definitive path, or do we stay with linear chains and accept constraints?

2. **Core Model**
- What minimum graph capabilities are required to unlock target analog-style effects credibly?

3. **Transition Posture**
- Do we plan a direct cutover once viable, or accept a temporary overlap period?
- What are the explicit parity/performance exit criteria?

4. **Product Surface Implications**
- What happens to Effects Studio in this phase (pause, narrow, or rebuild plan)?
- What authoring experiences are mandatory in the first graph-based iteration?

5. **Interop Stance**
- Is OFX guidance-level only, adapter-level later, or near-term requirement?

## What This Spike Should Produce

1. A clear go/no-go decision on pass-graph as the default runtime direction.
2. A concise architecture contract for graph semantics and authoring boundaries.
3. A transition memo with explicit cutover criteria and risk controls.
4. A short Effects Studio decision note for this transition phase.
5. A follow-on implementation project brief (active-ready).

## Migration/Transition Notes (Initial)

- No user-data migration commitment in this spike.
- Strong preference to avoid long-lived dual-runtime complexity.
- Likely implementation sequence:
1. build new runtime in `HypnoCore`
2. port key effects/chains into graph model
3. switch renderer to graph runtime
4. remove legacy runtime paths once parity/perf gates pass

## Risks To Track

- Rebuild scope could delay near-term product milestones.
- Temporary loss of effect parity while porting.
- Effects Studio work may be partially stranded and require explicit restart.
- Performance regressions if graph resource scheduling is under-specified.
- Authoring complexity could reappear in a new form if UX contracts are not explicit.

## Suggested Spike Method

1. Define minimal graph semantics in plain language using 3-5 representative analog pipelines.
2. Build one proof effect that is hard to express cleanly in the current chain model.
3. Compare output quality, performance, and authoring friction against current runtime.
4. Decide cutover strategy with explicit success/failure gates.
5. Publish an implementation brief and stop adding net-new complexity to legacy path.

## Related Projects

- [effects-chain-composition-spike](./effects-chain-composition-spike.md)
- [composition-timeline-pivot-spike](./composition-timeline-pivot-spike.md)
- [sidebar-windowization](../active/sidebar-windowization.md)
