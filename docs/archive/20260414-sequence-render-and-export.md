# Sequence Render and Export

This work is also effectively landed at the first meaningful level. Hypnograph can now export a full hypnogram as one finished movie through the shared sequence-time renderer. That export path is plan-driven rather than stitched from pre-rendered composition files, and it handles transitions, sequence-level effects, and audio in one render model.

The architectural source of truth is now:

- [render-pipeline](../reference/render-pipeline.md)

The most important remaining follow-ons are operational rather than foundational:

- selected-range sequence export instead of always rendering the whole hypnogram
- better export progress and operator feedback
- performance instrumentation around sequence export and preview handoff
- continued reuse of the same sequence-time model for preview playhead, scrubbing, and more deterministic sequence navigation

Supersedes:

- `docs/active/sequence-time-renderer.md`
- `docs/backlog/sequence-render-and-export.md`
