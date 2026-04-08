---
doc-status: in-progress
---

# Sequences

## Overview

This project is about turning Hypnograph's evolving history into a first real sequence-authoring surface.

The core model is now clear: there is one active working `Hypnogram` at a time. If the app is launched normally, that working hypnogram is the default autosaved `history.json` session. If a `.hypno` file is opened, that file replaces the active working hypnogram. Sequence UI and behavior should build on that document model rather than treating history as a separate architecture.

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
- Next slice: reduce the remaining runtime mirroring around document-level settings and then move into the first sequence strip or timeline surface.
- Follow-on slice: define the first sequence strip or timeline surface, including segment visibility, range selection, and how dense histories are made legible.
- Later slice: refine sequence transport and timeline interaction once a visible sequence range exists, especially around clip-level scrubbing and beginning/end affordances.

## Open Questions

- Should the top-level `Hypnogram.snapshot` remain as a stored document-poster image, or become a derived accessor that simply returns the first composition's preview image?
- What is the clearest first way to handle hundreds of history items in the strip: zoom, overview + focus, collapsing, or something else?
- Is moving or reordering compositions within the sequence in scope for this first project, or only something to leave open while the basic range-selection model settles?
- Before this project is done, revisit the `history` naming in both code and UI so it more honestly describes the unnamed scratch session or default working document rather than implying a separate model.
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
- Opening a `.hypno` file now replaces the active working hypnogram instead of appending into the default autosaved history document.
- The default `history.json` now effectively behaves as the unnamed fallback working hypnogram and is only autosaved while it remains the active document.
- `Save` and `Save As` now save the full current working hypnogram, while `Save Composition` and `Save Composition As` explicitly save only the current composition as a single-composition `.hypno`.
- File-open replacement now prompts to save only when the current active working document is a dirty file-backed hypnogram. The unnamed default history document is simply autosaved and replaced.
- `New` now starts a fresh working hypnogram, while `New Composition` inserts a new composition immediately after the current one in the active sequence.
- The working hypnogram is now owned directly by `Studio`, with `PlayerState` consuming that document instead of storing its own separate hypnogram.
- Playback transport now uses a three-state loop model (`off`, `composition`, `sequence`) plus an app-level `Generate at End` toggle. These are intentionally runtime behaviors, not hypnogram document state.
- Passive playback reaching the end of the sequence now either stops, loops the composition, loops the sequence, or continues generating depending on those transport settings, while explicit manual `Next` at the end still generates a new composition.
- The remaining architectural cleanup is narrower now: document ownership is settled, but some document-level settings are still mirrored across `Studio`, `LivePlayer`, and player configuration more than the desired end state.

## Next Refactor

This session is intentionally pausing here. The next clean architectural step is not to add more fields or more migration support, but to simplify the remaining runtime mirroring around the already-established model shape.

- Let document-level settings live as current-hypnogram state first, with runtime systems applying from and syncing back to that single source of truth.
- Remove avoidable mirrored state for those document-level settings where possible, especially where the current implementation is carrying both live runtime values and hypnogram copies only to keep them aligned.
- Use that cleaner ownership model as the base for the first horizontal sequence strip or timeline surface.

--- LLM IGNORE EVERYTHING BELOW THIS LINE FOR NOW ---

MISC ADDENDUM:

After we move Hypnogram up to Studio state:

- Can't seem to change output resolution

- Snapshot saving I think is causing pauses in transitions at the end of clips. It is crucial we don't interrupt playback.

- UX issue (old): There is a weird broken / mismatch pattern between the effects (chains) on Composition and Layer mostly in terms of the menus, but ultimately related to underlying out-of-date functionality in the Layer effect chain cycling.

- Rename the Playback menu to Sequence, also the History tab in Hypnograms panel should be renamed to "Sequence" or simply "Current"

- The ability to re-order items in the Sequence by drag-and-drop within the Hypnogram > Sequence (assuming the code can be re-used as we move to a Timeline view) would be a big win
- 
- The delineation between History and a currently open Hypnogram file needs to be possible first, and then clear on how to switch between them.  The endpoint of the bulk of non-timeline UI sequences will be getting to thise point of having sort of clear UX for switching between History "mode" and the current Hypnogram file.  How those relate and interact...

----

MORE MISC NOTES CAPTURE:

Just process this with me in chat. No coding minimal churn. Just give me a gathering of the thougths here without a bunch of lists:

Okay, so I think, um... With a quick fix for saving hypnograms fully, their full sequence versus just an individual sequence. That whole thing is a pretty big win. And now it puts a lot of pressure on the render pipeline. I'm so curious if there's some sort of, like, screen capture camera view version of the render that can happen. Both for individual hypnograms, actually, and for those sequences, because it seems like we could greatly reduce the render pipeline if I could just stream out to disk the, um, output of the player. Which I was defeated before in trying that, but I think I'll ask again. And they just research it a bit. Otherwise, The big gaps for composition have to do with just, like, laying out the timeline. And I'm starting to see that my idea of a composition is basically a compound layer. And so it would be nice to have clips be able to start and stop, kind of like they look like in the timeline now, to have the begin, the in and out points, actually be. as represented on the timeline view. Such that each sequence is basically a compound clip. Um, Yeah. Then it just makes it sort of a manageable unit. I'm just trying to decide how much that varies, differs from what's already available. in a nonlinear editor. As... The timeline. Um, It's sort of like a timeline in which I can go to any point in the playhead and press a button to get a like a random clip. Um, and then be able, the mechanics of it is they can quickly cycle that clip to other random clips until it's when I want. And then it also picks a random length. Um, I think that's all pretty interesting in a way. I still think I haven't noted anywhere that I want the settings to be able to... First of all, the most critical setting we have to add next, I think, is for it to stop playing at the end of the sequence. or to loop the sequence, in fact. Versus just loop a clip. Um... And I think that's gonna be just, again, a multimodal selector on the loop button. Maybe it has 3 modes. Loop clip, loop sequence, or no loop, right? That's a good idea, actually. I think that's probably the most compact way to handle it. Um, We still need the go to end, go to beginning buttons. And we still need a horizontal timeline layout for the sequences. I'm pretty sure. Um, That print free sequence, the amount of seconds it is, and it might have it positioned in the timeline. To have a relative size to the total. For the lakes of the composition, which means I might be able I might need to be able to scroll horizontally that whole timeline in case it gets long. And even Zoom can scale it. Which is probably not terribly difficult to implement, but it's just the UX might get weird. Um, It's a timeline. In the end, it is a timeline. So, I think what we have is, like, the main timeline view, and then... when you click on a clip, it shows all of its layers beneath it. Um, I think that's how it works. Um, Or it might actually be, the timeline is at the very bottom. When you click on a clip, it shows all the layers on top. so that the play bar can stay in place or whatever the timeline can stay in place. And the layers can just go up.


RESPONSE:

Yeah, I think you’re seeing the real shape now.

The full-sequence save work quietly changed the center of gravity. Before, sequences were somewhat conceptual. Now that a whole working hypnogram can actually be saved as one document, the app is already behaving much more like a lightweight sequence editor, and that naturally makes render and timeline questions feel urgent instead of theoretical.

On the render question, I think your instinct is good to revisit it. A “capture what the player is already producing” path is attractive because it avoids rebuilding the world a second time. But the catch is still the same one that probably beat you before: the preview player is optimized for interactive playback, not deterministic export. As soon as you want exact duration, guaranteed frame cadence, reliable transitions, clean end-of-sequence behavior, and no dropped frames, screen-style capture starts feeling shaky. It may still be useful as a lower-grade or “fast export” path, though. That seems like the real opportunity to me. Not replacing the proper renderer, but maybe having a cheap capture-based export mode for certain cases if the quality holds up well enough. That would be worth researching again, especially now that the sequence model is more real.

What you’re saying about compositions as compound layers also feels important and clarifying. I think that’s the right mental model. A composition is becoming less like “one state in history” and more like “one higher-order clip.” Once that clicks, a lot of the timeline design follows pretty naturally: the sequence is a row of compound clips, each with duration, in/out, relative size, and reorderability; then selecting one reveals its internal layer structure. That does start to rhyme with a nonlinear editor, but the difference still feels meaningful to me. Hypnograph’s authoring gesture is not “place media precisely on a timeline from scratch.” It’s much more like “generate a clip-shaped visual event, audition variants quickly, keep the one that feels right, and then arrange those larger units.” That’s not nothing. It’s actually a pretty distinct workflow.

So I think the architecture you’re circling is probably:
the bottom-most stable surface is the sequence timeline, horizontally laid out, scrollable, probably zoomable, with each composition shown as a compound clip scaled by duration. Then selecting one clip reveals its internal layer timeline above it. That feels cleaner than trying to have everything share one vertical stack all the time. It also preserves the current play controls more easily, because the transport and sequence navigation can stay anchored while the selected-composition detail view changes above.

And yes, the playback mode issue sounds like the next truly necessary behavior setting. Right now “loop current composition” is too small a concept for where the app has gone. A three-state loop model makes immediate sense: no loop, loop composition, loop sequence. That’s compact, expressive, and probably maps cleanly onto the existing loop control without adding too much surface area. It also helps clarify what “Play” even means once you’re clearly inside a sequence.

So my overall read is: this is becoming a timeline tool, but not in a generic NLE way. It’s becoming a compound-clip sequence instrument, where each clip is itself a generative layered composition. That distinction feels like the right north star to hold onto, because it keeps the product from drifting into “just another editor” while still letting you borrow the structural strengths of timeline-based UI.
