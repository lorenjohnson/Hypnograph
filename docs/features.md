# Features

## Onboarding

On first launch, Hypnograph requires source setup before normal playback. It supports Apple Photos (all photos/videos or selected album), folder-based sources with recursive scan, and combined use of both source types at once.

## Continuous Random Playback

After sources are configured, playback starts immediately and continues autonomously without operator intervention. The system continuously selects sources, generates successive Compositions, and advances through them as a stream. This feature includes parameters for random Composition generation: max layer count (default 1), length range in seconds, and effect-change behavior (composition/per-layer and frequency/percentage controls).

## Playback Controls

Playback controls include play/pause for the current Composition and a toggle to loop the current Composition. Loop repeats the current Composition while it is on; otherwise a Composition plays and then transitions to the next randomly generated Composition, or to the next entry in history if not at the end of the history.

## Composition-Level Controls

Composition-level controls shape the entire current Composition across all layers. This includes transition style between Compositions, aspect ratio selection (including standards such as 16:9, 9:16, etc), fill-based canvas behavior, and source framing mode (fit/fill) rules for applying to individual Sources. These settings persist across newly generated Compositions and are not currently randomized. In the UI, these controls appear above the Layers as Composition-level settings.

## Layer Composition

Layers can be added, deleted, and adjusted independently from Composition-level settings. Adding new Layers can be done via random selection or selection of an explicit media Source from disk or Apple Photos. Additionally, layer blend mode and in/out ranges for the underlying source video can be adjusted via a thumbnail timeline view attached to player controls. Audio mute, solo, and visibility toggles are available per layer.

Number keys select the corresponding Layer in the current Composition (`1` selects layer 1, `2` selects layer 2, etc.), and backtick selects the Composition context. While a selection key is held, playback enters a temporary preview mode showing only that selection and bypassing effects for quick inspection.

## Settings Dialog

Hypnograph includes a dedicated settings dialog (instead of direct file editing) with `General` and `Advanced` tabs. General includes audio output device selection, settings-folder quick access, history controls (clear history and max length, default ~200), render/snapshot destination settings, and render destination mode (`disk + Apple Photos`, `Apple Photos only`, or `disk only`). General also contains the install action for CLI/Finder integration (the operational behavior belongs to the separate CLI/Finder feature below). Advanced currently contains feature flags for Live Mode and Effects Composer, plus keyboard-override behavior for space/tab accessibility handling.

## CLI and Finder Action

Hypnograph includes a CLI + Finder Action integration path that is installed from Settings. The Hypnograph CLI supports quick source additions from command line context (for example, adding a directory path as a source; exact command syntax should be re-verified). Finder integration installs a Quick Action so files/folders can be added to Hypnograph sources from the Finder context menu. Current implementation is legacy and needs maintenance, but this capability is intentionally retained.

## History Buffer

As playback advances, Compositions are stored in a configurable history buffer (operator recalls ~200 default), with navigation/recall and clear operations. The UI buttons that look like rewind/fast-forward are history back/forward controls (not transport scrubbing).

## Save and Reopen

Saving writes a JSON Hypnogram metadata file (the reconstructable recipe/state), not rendered media. Reopening that JSON file restores one or more saved Compositions. Render/export is separate: rendering writes actual media files for playback/sharing, and those rendered outputs can be saved to disk and optionally mirrored to Apple Photos when permissioned. Rendered media can be used as Sources, but do not carry the original editable Hypnogram spec.

## Render and Screenshot Export Pipeline

Users can export rendered video from the current Composition and capture frame screenshots via hotkey/menu. Output destination is configurable (desktop by default, per operator recall), with optional Apple Photos write-back when permissioned.

## Effects and Effect Chain Library

Effects can be applied over a whole composition or per layer. Chains can be edited, saved, overwritten, and reused from a global library. Individual effects are parameterized and can be treated as part of chain workflows.

## Favorites, Exclude, and Delete

Hypnograph supports a family of quick content actions (hotkeys + command menu): favorite, exclude, and delete. Favoriting saves the full hypnogram spec into app-local sidecar persistence (e.g., favorites JSON in Application Support) and can be reopened from the legacy favorites/recents browser. Excluding removes the current source from future random selection and replaces it immediately when needed; exclusion state is persisted locally (JSON in Application Support) and mirrored to Apple Photos exclusion storage when Photos permissions are available. Delete (`D`) marks the selected source/layer source for deletion review, persists that mark locally, and mirrors it to a deleted album/store when Photos permissions are available; it intentionally does not hard-delete media in-place. This feature family also includes a legacy browser window that lists Favorites and Recents and allows opening entries one-by-one. Recents appears to be history-derived (likely subset behavior), and that relationship is an open cleanup gap.

## Live Mode / Performance Output (Feature-Flagged)

Live mode allows sending the current Composition to an external display for slideshow/performance use. A local in-window preview of the live output can be toggled on/off. Live output loops the currently sent Composition until another one is sent; when replaced, it transitions using the configured transition style. Live mode has its own audio routing controls (audio device and volume), intentionally architected to stay decoupled from core playback paths.

## Effects Composer (Feature-Flagged)

A dedicated Effects Composer supports authoring Metal-based effects with live code editing, parameter mapping, and preview against selected/random sources. It is available but not mainline for all users and may later split into a separate app.
