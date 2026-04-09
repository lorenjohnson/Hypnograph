---
doc-status: in-progress
---

# Sequences

## Overview

This project is about turning Hypnograph's evolving history into a first real sequence-authoring surface.

The core model is now clear: there is one active working `Hypnogram` at a time. If the app is launched normally, that working hypnogram is the default autosaved `default-hypnogram.hypno` session. If a `.hypno` file is opened, that file replaces the active working hypnogram. Sequence UI and behavior should build on that document model rather than treating history as a separate architecture.

The next visible milestone is a sequence strip or timeline that makes the compositions in the current working hypnogram visible and editable as an ordered range. Export remains follow-on work and is tracked separately in [sequence-render-and-export.md](/Users/lorenjohnson/dev/Hypnograph/docs/backlog/sequence-render-and-export.md) and [sequence-fcpxml-export.md](/Users/lorenjohnson/dev/Hypnograph/docs/backlog/sequence-fcpxml-export.md).

## Rules

- MUST keep the current history-based model usable while adding sequence authorship on top of it.
- MUST prototype a history timeline strip that uses the same general styling language as the existing composition or layer timelines.
- MUST let the operator set an in point and an out point across history.
- MUST let history range selection snap to whole-hypnogram boundaries rather than arbitrary sub-clip positions.
- MUST make the history strip capable of dealing with large histories rather than assuming only a handful of visible items.
- MUST treat history persistence convergence with the saved `Hypnogram` document format as in scope for this project rather than as unrelated cleanup.
- MUST treat `currentCompositionIndex` as optional multi-composition document state on `Hypnogram`, not as a history-only sidecar format.
- MUST establish composition-level preview image fields so sequence and history UI can render composition thumbnails without inventing a history-only image model.
- MUST treat document-level viewing or restore context such as aspect ratio, player or output resolution, source framing, and transition style or duration as optional state on `Hypnogram` rather than only as app-global settings.
- MUST deprecate the previous app-global persistence locations for those document-level viewing fields rather than carrying forward migration support for them.
- MUST keep `playRate` as composition-level authored data rather than moving it into hypnogram-level document state.
- MUST treat loop mode and `Generate at End` as app/runtime transport behavior, not as document state on `Hypnogram`.
- SHOULD treat show or hide behavior for the history timeline and the existing hypnogram timeline as one coordinated UX decision.
- MUST keep a clear distinction between passive end-of-sequence behavior and explicit manual navigation.
- SHOULD add clearer transport affordances for jumping to the beginning and end of the active range or history, if that remains the clearest MVP control shape.
- MUST keep export concerns from taking over the first sequence UI and behavior decisions.
- MUST NOT let longer-term naming or model-cleanup questions block the first usable version.

## Plan

- Completed slice: history persistence now validates as a shared multi-composition `Hypnogram`, with composition-level previews and canonical `currentCompositionIndex`.
- Completed slice: document-level restore context now lives on `Hypnogram`, not in app-global settings. `playRate` remains composition-level.
- Completed slice: the active working document model now distinguishes between the unnamed default session and file-backed `.hypno` documents without treating history as a different data model.
- Completed slice: transport behavior is now split cleanly between loop mode (`off`, `composition`, `sequence`) and the app-level `Generate at End` toggle. Manual next-at-end still generates, while loop-sequence also wraps manual sequence navigation.
- Completed slice: the active working `Hypnogram`, `currentCompositionIndex`, and document revision are now owned directly by `Studio`, while `PlayerState` has been reduced to playback-local concerns.
- Completed slice: document-level playback and viewing settings are now read primarily from the working `Hypnogram`, and `PlayerConfiguration` has been reduced back toward generation-only concerns.
- Completed slice: `Sequence` now lives in its own panel instead of being a tab inside `Hypnograms`, and that panel supports basic drag-and-drop composition reordering.
- Next slice: define the first richer sequence strip or timeline surface, including segment visibility, range selection, and how dense histories are made legible.
- Follow-on slice: refine the first sequence strip once it exists, especially around density, scrolling, zoom, and reordering.
- Later slice: refine sequence transport and timeline interaction once a visible sequence range exists, especially around clip-level scrubbing and beginning/end affordances.

## Open Questions

- Should the top-level `Hypnogram.snapshot` remain as a stored document-poster image, or become a derived accessor that simply returns the first composition's preview image?
- What is the clearest first way to handle hundreds of history items in the strip: zoom, overview + focus, collapsing, or something else?
- That same pass should resolve scratch-session edge cases, such as what should happen after explicitly saving the scratch session as a file-backed hypnogram and whether the default scratch session should immediately reset to a fresh working document afterward.
- The project will also need an easy way to import or merge one hypnogram into another and to move compositions around within the current sequence once that authoring surface exists.

## Architecture Direction

The current working `Hypnogram` should be the central Studio document model.

That means:
- `Studio` owns the active working `Hypnogram`, `currentCompositionIndex`, and the document revision used to signal mutation.
- `PlayerState` now holds playback-local concerns such as pause state, current layer selection, scrubbing offsets, load failures, and frame-presentation tracking.
- Document-shaped state that loads from a file, updates while authoring, and saves back into the file should live on the current working `Hypnogram`, not be mirrored across multiple semi-authoritative runtime homes.
- App-global concerns such as libraries, permissions, and global preferences should remain outside the document.

## Current Implementation State

- History persistence now uses the shared multi-composition `Hypnogram` schema rather than a separate history-only shape.
- Composition-level `snapshot` and `thumbnail` fields are now in place and are used for history-item previews.
- `currentCompositionIndex` is now treated as optional document state on `Hypnogram`.
- Document-level viewing and playback settings such as aspect ratio, player or output resolution, source framing, and transition settings have been moved off app-global settings and onto `Hypnogram`.
- Opening a `.hypno` file now replaces the active working hypnogram instead of appending into the default autosaved fallback hypnogram.
- The default `default-hypnogram.hypno` now behaves as the unnamed fallback working hypnogram and is only autosaved while it remains the active document.
- `Save` and `Save As` now save the full current working hypnogram, while `Save Composition` and `Save Composition As` explicitly save only the current composition as a single-composition `.hypno`.
- File-open replacement now prompts to save only when the current active working document is a dirty file-backed hypnogram. The unnamed default fallback hypnogram is simply autosaved and replaced.
- `New` now starts a fresh working hypnogram, while `New Composition` inserts a new composition immediately after the current one in the active sequence.
- The working hypnogram is now owned directly by `Studio`, with `PlayerState` consuming that document instead of storing its own separate hypnogram.
- `Sequence` now lives in its own dedicated panel, while `Hypnograms` has narrowed back to saved-entry browsing.
- The current Sequence panel now supports drag-and-drop composition reordering, with selection preserved by composition identity so the same move semantics can be reused by a later timeline surface.
- Playback transport now uses a three-state loop model (`off`, `composition`, `sequence`) plus an app-level `Generate at End` toggle. These are intentionally runtime behaviors, not hypnogram document state.
- Passive playback reaching the end of the sequence now either stops, loops the composition, loops the sequence, or continues generating depending on those transport settings, while explicit manual `Next` at the end still generates a new composition.
- Document-level playback and viewing settings are now sourced primarily from the working `Hypnogram`, with only the live player keeping a small runtime copy of the values it actively renders with.
- `PlayerConfiguration` has been reduced back to generation-oriented state rather than acting as a second source of truth for document-level playback settings.

## Next Refactor

This session is intentionally pausing here. The next refactor should address the lingering fallback-session naming and behavior mismatch now that the app clearly has one active working `Hypnogram` at a time.

- Reframe the default `default-hypnogram.hypno` session more explicitly as the unnamed scratch or default working hypnogram rather than implying a separate model or mode.
- Update code and UI naming where needed so `history` no longer suggests a different architecture from opened `.hypno` files.
- Resolve the scratch-session behavior edge cases, especially what should happen after explicitly saving the scratch session as a file-backed hypnogram and whether a fresh unnamed working session should be created immediately afterward.
- Use that refactor to make the relationship between the default scratch session and opened file-backed hypnograms clearer before moving on to the first visible sequence strip or timeline surface.

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
