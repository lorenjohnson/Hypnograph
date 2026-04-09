---
doc-status: in-progress
---

# Sequences

## Overview

This project is about turning Hypnograph's multi-composition working state into a real sequence-authoring surface.

The core model is now clear: there is one active working `Hypnogram` at a time. If the app is launched normally, that working hypnogram is the default autosaved `default-hypnogram.hypno` fallback file. If a `.hypno` file is opened, that file replaces the active working hypnogram. Sequence UI and behavior should build on that document model rather than treating sequence editing as a separate architecture.

The next visible milestone is a sequence strip or timeline that makes the compositions in the current working hypnogram visible and editable as an ordered range. Export remains follow-on work and is tracked separately in [sequence-render-and-export.md](/Users/lorenjohnson/dev/Hypnograph/docs/backlog/sequence-render-and-export.md) and [sequence-fcpxml-export.md](/Users/lorenjohnson/dev/Hypnograph/docs/backlog/sequence-fcpxml-export.md).

## Rules

- MUST keep one active working `Hypnogram` as the central sequence model.
- MUST keep composition previews, ordering, and `currentCompositionIndex` as document state on `Hypnogram`.
- MUST keep loop mode and `Generate at End` as runtime transport behavior, not document state.
- MUST keep the first visible sequence surface lightweight and editable before taking on export- or timeline-heavy work.
- MUST keep later timeline work aligned with the same composition ordering and selection semantics already used by the Sequence panel.

## Plan

- Completed: multi-composition `Hypnogram` persistence, previews, document-level restore settings, and sequence-aware save/open behavior.
- Completed: loop and end-of-sequence runtime behavior is now separate from document state.
- Completed: `Studio` owns the working `Hypnogram`, and the unnamed fallback working hypnogram now resets to a fresh default after it is explicitly saved out as a file-backed `.hypno`.
- In Progress: the first richer sequence strip is now embedded directly in playback controls, with current selection, drag-and-drop reordering, and horizontal scrolling.
- Next: refine the embedded sequence lane until it is a solid first timeline surface, then decide what timeline-specific editing affordances come next.

## Open Questions

- Should the top-level `Hypnogram.snapshot` remain stored, or simply derive from the first composition preview?
- What is the clearest first way to handle very long sequences in the later strip or timeline: zoom, overview plus focus, collapsing, or something else?
- What is the first good import or merge flow for bringing one hypnogram into another?

## Architecture Direction

The current working `Hypnogram` should be the central Studio document model.

That means:
- `Studio` owns the active working `Hypnogram`, `currentCompositionIndex`, and the document revision used to signal mutation.
- `PlayerState` now holds playback-local concerns such as pause state, current layer selection, scrubbing offsets, load failures, and frame-presentation tracking.
- Document-shaped state that loads from a file, updates while authoring, and saves back into the file should live on the current working `Hypnogram`, not be mirrored across multiple semi-authoritative runtime homes.
- App-global concerns such as libraries, permissions, and global preferences should remain outside the document.

## Current Implementation State

- The app now works from one active multi-composition `Hypnogram` at a time.
- The unnamed fallback working file is `default-hypnogram.hypno`; opening a `.hypno` replaces it rather than merging into a separate sequence/history model.
- `Save` and `Save As` save the full working hypnogram; composition-only save is explicit.
- Saving the unnamed fallback working hypnogram as a real `.hypno` now resets the persisted fallback file to a fresh default.
- `Studio` owns the working `Hypnogram`, `currentCompositionIndex`, and document mutation flow.
- Playback loop and `Generate at End` are runtime transport behavior only.
- The current sequence surface now lives inside playback controls rather than in a separate Sequence panel.
- Layer trim strips now stay visible together, and the embedded sequence lane shares that same playback-controls context.

## Next Refactor

Keep iterating on the embedded sequence lane until it earns its place as the first real timeline surface.

- Preserve the current composition ordering and selection semantics as the basis for the lane.
- Keep reordering reusable for a later fuller timeline view.
- Improve density, scrolling feel, and visual legibility before adding heavier timeline mechanics.



--- LLM IGNORE EVERYTHING BELOW THIS LINE FOR NOW ---

MISC ADDENDUM:

- Snapshot saving I think is causing pauses in transitions at the end of clips. It is crucial we don't interrupt playback. See holding/preview-capture-debounce branch for an out-of-date first pass that has yet been untested. This attempt seemd to involved too much code and complexity for my taste, and I want something simpler, though some of the ideas are probably right.

----

Notes about the sequence/timeline work coming, including rendering of full sequence:

The full-sequence save work quietly changed the center of gravity. Before, sequences were somewhat conceptual. Now that a whole working hypnogram can actually be saved as one document, the app is already behaving much more like a lightweight sequence editor, and that naturally makes render and timeline questions feel urgent instead of theoretical.

Compositions as compound layers also feels important and clarifying. I think that’s the right mental model. A composition is becoming less like “one state in history” and more like “one higher-order clip.” Once that clicks, a lot of the timeline design follows pretty naturally: the sequence is a row of compound clips, each with duration, in/out, relative size, and reorderability; then selecting one reveals its internal layer structure. That does start to rhyme with a nonlinear editor, but the difference still feels meaningful to me. Hypnograph’s authoring gesture is not “place media precisely on a timeline from scratch.” It’s much more like “generate a clip-shaped visual event, audition variants quickly, keep the one that feels right, and then arrange those larger units.” That’s not nothing. It’s actually a pretty distinct workflow.

I think the architecture you’re circling is probably:
the bottom-most stable surface is the sequence timeline, horizontally laid out, scrollable, probably zoomable, with each composition shown as a compound clip scaled by duration. Then selecting one clip reveals its internal layer timeline above it. That feels cleaner than trying to have everything share one vertical stack all the time. It also preserves the current play controls more easily, because the transport and sequence navigation can stay anchored while the selected-composition detail view changes above.

So my overall read is: this is becoming a timeline tool, but not in a generic NLE way. It’s becoming a compound-clip sequence instrument, where each clip is itself a generative layered composition. That distinction feels like the right north star to hold onto, because it keeps the product from drifting into “just another editor” while still letting you borrow the structural strengths of timeline-based UI.

Thoughts about rendering the whole sequence, which will also become a priority maybe before even building the richer timeline ui:

A “capture what the player is already producing” path is attractive because it avoids rebuilding the world a second time. But the catch is still the same one that probably beat me before: the preview player is optimized for interactive playback, not deterministic export. As soon as I want exact duration, guaranteed frame cadence, reliable transitions, clean end-of-sequence behavior, and no dropped frames, screen-style capture starts feeling shaky.
