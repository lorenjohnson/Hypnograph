---
last_reviewed: 2026-01-07
---

## RESEARCH & DEVELOPMENT

Completed items live in `archive/index.md`.

## Research & Development

- [ ] Make Player View a bottom of screen strip instead of a side quarter window. Play with "light up punch buttons" for turning and and off sources and a different color to indicate the currently selected source.
- [ ] Explore how some watch sort of mode where individual sources in a layered montage hypnogram change one by one randomly might work. Start with prototype just to see how the experience feels and if it is worth integrating.
- [ ] Explore "Channels" for Hypnograph watching: e.g., select a pin on a map + max radius to constrain random clip selection; or time-based channels with begin/end date (or a slider for time period before/after a date). Or using Apple Foundation to formulate a PHAsset query (e.g. "All photos in and around Berlin, Germany in 2025")
- [ ] Custom Metal blends modes for better destructive shaders/effects. How to integrate our own Metal shaders as Blend Mode options.
- [ ] Auto blend mode sensing (like based on the relative brightness of the source images). I think I am already doing something like that.
- [ ] Midi mapping, Mic input, MIDI Clock, OSC
- [ ] Bring back randomized effect as an option for randomized hypnogram generation
- [ ] Live Mode is a bit confusing in this product
- [ ] I want there to be a history of Hypnograms regardless of whether or not they were saved so we can always go back when one looked good. The history should be maybe 100 or so back or ? maybe configurable in settings.json with a default setting of 10
- [ ] I am questioning whether effects chains ("Treatments")should be named or if they maybe are just a thumbnail and pressing on the Treatment thumbnail applies the treatment or maybe a small button on the thumbnail takes a snapshot of the current hypnogram to be the new thumbnail for that treatment.

## KNOWN ISSUES / BUGS

- [ ] Save and Render: Rendering started and another flash message appear at the same time and one of those messages is extraneous 
- [ ] When the Player is not playing / when it is all still images blend modes don't apply and I can't "flash" to a new layer and see it without effects like I can when videos are playing. It should work/work the same in both scenarios. This is also true if I change effects when the player is paused and it is all videos...
- [ ] Updating an Effect Chain title from where it is applied (e.g. global), then saving back to library just seemed to create a new Library Entry instead of saving back to the original library entry.
- [ ] Rendering/saving some Hypnograms results in an error: "🔴 RenderEngine.export failed - RenderError: Export failed: Cannot Decode. Render job failed: The operation couldn’t be completed. (Hypnograph.RenderError error 6.)"
any effects load operation were done first
- [ ] Finder action not installing - Automator action fails.

## MINOR PROJECTS

- [ ] Add settings window and splash screen, branding stuff? "What you are looking for is who is looking." - St. Francis of Assisi
- [ ] Feature flag Live mode as a possible optional feature... to eventually be a paid add on?
- [ ] Hypnograph: Put what is in HUD view into the top of the Player Settings modal, eliminating the HUD View. Player Settings may get retitled, not sure. But it now takes up more vertical space and goes to top left of screen. We may need to iterate on the styling and what actually stays, as some things in the HUD may just go away or move elsewhere.
- [ ] Hypnograph Favorites/Recents window. Recents should just be a list of the history items. Favorite should be ordered from newest to oldest?
- [ ] Window state not saved in Hypnograph. Maybe save it. Also tab when there are no windows shown or to restore, shows a default set of Player Settings and Effects.
- [ ] Consider new default for storage location (e.g. `~/Movies/Hypnograph` instead of `~/Library/Application Support/Hypnograph/recipes`)
- [ ] Confirm the Add Source functionality (which should be mapped to ".") still works.
- [ ] Add a "+ New Hypnogram" button on the player view
- [ ] Tweaks to the IFrame Compress effect, because I like it:
  - [ ] Make the period between iframe freezes more jittery by default and maybe add a setitng after trying it out
  - [ ] Same with the other params, more jitter by default but with anticipation of adding a param
  - [ ] When it is done sticking to a mask or whatever you'd call it, it releases seemingly suddenly. Make it more of a fade or erosion.
- [ ] Game Controller mapping revamp back to essentials only

## PROJECTS

## Improve windowing system to be more idiomatic / Swift native while still be unobtrusive

The hidden work here is actually desciding and designing the UI/UX I want first. Which windows exist and what goes in them and what do they look like?

## export-clip-history-fcpxml

- [ ] Add a Hypnograph menu item to Export entire History to an open standard timeline format (for import by a NLE): `projects/backlog/export-clip-history-fcpxml`

## volume-leveling

Volume leveling option in Player Settings (keeps relative db same across all shown Hypnograms). Depends on: Metal Playback Pipeline (boundary hooks): `projects/volume-leveling`

## location-overlay-effect

Per-source effect that overlays a source asset's location as text (Phase 1: coordinate short form; Phase 2: reverse-geocoded place name): `projects/backlog/location-overlay-effect`

## save-sequences

- Goal: save and render a contiguous range of clips from clip history (In/Out selection by clip id), without re-introducing "Sequence mode":`projects/save-sequences`

## Integrate a Roadmap feature into both apps

Appears as a command under Hypnograph / Divine left menu and opens a conventional Swift or Swift UI Mac OS window

- [ ] Show a list of upcoming features with a vote option and status of completion

## Prepare for Beta Release/TestFlight

- [ ] Apple Developer signup, App Store Connect, TestFlight release
- [ ] Collect testers, sort paths, finalize icon

## Basic Library Manager view for managing sets of items (for use by and modeld after current Effects Manager)

- [ ] Abstract for use by both the Effects Chains Library and Hypnogram Sets
- [ ] They have a very similar "library/set" manager UX
- [ ] Use a generalized Library Manager view that can be used by both
- [ ] You can add a Hypongram recipe to a set or the currently displaying hypnogram to the set.
- [ ] You can rename a set.
- [ ] You can delete a set.
- [ ] You can merge a set from disk into the existing set, or load it to replace the current set
- [ ] For Hypnogram sets this probably replaces the Favorites system for now. 
- [ ] To Favorite is to add a Hypnogram to the current set. 
- [ ] Hypnogram sets like Effect Filter Chain libraries are saved by default as the current session always, and can also be "Saved As" as well as explicitly opened from disk. 
- [ ] When opening another set you can choose to "Merge" it into the existing set. 
- [ ] The Library Manager allows drag and drop of items in the set in the left panel not just like within the filter chains (which currently exists). 
- [ ] For Hypnogram sets and for FIlter Chain sets you can drag and drop the order of items in the left panel.
- [ ] You can re-order individual Hypnograms within in a set

## Current Hypnogram / Recipe window

- [ ] Each source can be disabled or deleted
- [ ] Each source can be dragged to reorder
- [ ] The blend mode can be changed for each source
- [ ] A new source can be added at the end and it can either be "New Random" or "New from File (opens file open dialog)"
- [ ] The opacity can be changed for each source
- [ ] You can change the playback speed for each source (if easy)
