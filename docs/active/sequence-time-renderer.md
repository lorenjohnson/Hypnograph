---
doc-status: in-progress
---

# Sequence-Time Renderer

This project established the first shared sequence-time model and used it to land a real full-sequence export path.

The architecture reference now lives here:

- [render-pipeline](../reference/render-pipeline.md)

# Outcome

The important thing this project proved is that Hypnograph can export a full hypnogram from one sequence-time plan without falling back to stitched pre-rendered composition movies. That path now handles transitions, sequence-level effects, and audio in one finished export.

# Remaining Direction

The next work should use the same sequence-time model for playhead-aware preview, scrubbing, and more deterministic sequence navigation. The reference document above should be treated as the architecture source of truth rather than this project note.
