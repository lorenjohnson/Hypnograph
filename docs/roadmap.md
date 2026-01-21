---
last_reviewed: 2026-01-07
---

# Roadmap

## Research & Development

- [ ] Vision smart framing (Human Centering): bias `SourceFraming.fill` toward detected subjects without revealing edges.
- [ ] Make Player View a bottom of screen strip instead of a side quarter window. Play with "light up punch buttons" for turning and and off sources and a different color to indicate the currently selected source.
- [ ] Explore how some watch sort of mode where individual sources in a layered montage hypnogram change one by one randomly might work. Start with prototype just to see how the experience feels and if it is worth integrating.
- [ ] Custom Metal blends modes for better destructive shaders/effects. How to integrate our own Metal shaders as Blend Mode options.
- [ ] Auto blend mode sensing (like based on the relative brightiness of the source images). I think I am already doing something like that.
- [ ] Midi mapping, Mic input, MIDI Clock, OSC
- [ ] Bring back randomized effect as an option for randomized hypnogram generation
- [ ] Live Mode is a bit confusing in this product
- [ ] I want there to be a history of Hypnograms regardless of whether or not they were saved so we can always go back when one looked good. The history should be maybe 100 or so back or ? maybe configurable in settings.json with a default setting of 10
- [ ] I am questioning whether effects chains ("Treatments")should be named or if they maybe are just a thumbnail and pressing on the Treatment thumbnail applies the treatment or maybe a small button on the thumbnail takes a snapshot of the current hypnogram to be the new thumbnail for that treatment.

## Known Issues / Bugs
- [ ] Save and Render: Rendering started and another flash message appear at the same time and one of those messages is extraneus 
- [ ] When the Player is not playing / when it is all still images blend modes don't apply and I can't "flash" to a new layer and see it without effects like I can when vidoes are playing. It should work/work the same in both scenarios.
- [ ] Updating an Effect Chain title from where it is applied (e.g. global), then saving back to library just seemed to create a new Library Entry instead of saving back to the original library entry.
- [ ] Rendering/saving some Hypnograms results in an error: "🔴 RenderEngine.export failed - RenderError: Export failed: Cannot Decode. Render job failed: The operation couldn’t be completed. (Hypnograph.RenderError error 6.)"
any effects load operation were done first
- [ ] Finder action not installing - Automator action fails.

## Minor Projects:
- [ ] Clip slicing: for video sources, preserve a random `startTime` when it can play continuously for `targetDuration` without hitting the end; otherwise clamp `startTime` back so it can play to the end without looping; if the asset is shorter than `targetDuration`, use `startTime = 0` and loop the full asset.
- [ ] Confirm the Add Source functionality (which should be mapped to ".") still works.
- [ ] Hypnograph: Put what is in HUD view into the top of the Player Settings modal, eliminating the HUD View. Player Settings may get retitled, not sure. But it now takes up more vertical space and goes to top left of screen. We may need to iterate on the styling and what actually stays, as some things in the HUD may just go away or move elsewhere.
- [ ] Hypnograph Favorites/Recents window. Recents should just be a list of the history items. Favorite should be ordered from newest to oldest?
- [ ] Flash of image before processed in Player should be avoided/eliminated. Add a Transitions setting for what happens between Hypnograms. Maybe a Player setting for Transition Style with options: None, Fade, Punk (random dissolve)?
- [ ] Window state not saved in Hypnograph. Maybe save it. Also tab when there are no windows shown or to restore, shows a default set of Player Settings and Effects.
- [ ] Feature flag Live mode as a possible optional feature... to eventually be a paid add on? 
- [ ] Add "Player Settings" style control panel for Divine with settings: Allow Reversed toggle, Max Card (int)
- [ ] Add a "+ New Hypnogram" button on the player view
- [ ] Tweaks to the IFrame Compress effect, because I like it:
  - [ ] Make the period between iframe freezes more jittery by default and maybe add a setitng after trying it out
  - [ ] Same with the other params, more jitter by default but with anticipation of adding a param
  - [ ] When it is done sticking to a mask or whatever you'd call it, it releases seemingly suddenly. Make it more of a fade or erosion.
- [ ] Divine: Save layouts somehow (Snapshots are a good start), but saving a recipe for restore would be a better first step probably
- [ ] Consider new default for storage location (e.g. `~/Movies/Hypnograph` instead of `~/Library/Application Support/Hypnograph/recipes`)
- [ ] Game Controller mapping revamp back to essentials only

## Project: Split Docs by App + Shared Frameworks

Clarify docs ownership now that we have two distinct apps (Hypnograph + Divine) sharing `HypnoCore` and other frameworks.

- Goal: keep shared/core docs in `docs/`, and move app-specific docs to:
  - `Hypnograph/docs/`
  - `Divine/docs/`
- Scope: docs-only refactor (move files + update links); no code changes required.

## Project: Export entire History to an open standard timeline format (for import by a NLE)

- [ ] Add a Hypnograph menu item to Export entire History to an open standard timeline format (for import by a NLE)

## Project: Smart Framing (Human Centering)

Bias `SourceFraming.fill` to keep detected subjects (head/body) in-frame without revealing empty edges.

- Docs: `docs/projects/20260120-smart-framing-human-centering/overview.md`
- Plan: `docs/projects/20260120-smart-framing-human-centering/implementation-planning.md`

## Project: Volume Leveling

Volume leveling option in Player Settings (keeps relative db same across all shown Hypnograms). Depends on: Unified Player Architecture.

- Docs: `docs/projects/20260116-volume-leveling/overview.md`
- Plan: `docs/projects/20260116-volume-leveling/implementation-planning.md`

## Project: Save Sequences

- Goal: save and render a contiguous range of clips from clip history (In/Out selection by clip id), without re-introducing "Sequence mode".
- Docs: `docs/projects/20250116-save-sequences/overview.md`
- Plan: `docs/projects/20250116-save-sequences/implementation-planning.md`

## Project: Basic Library Manager view for managing sets of items (for use by and modeld after current Effects Manager)
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

## Project: Current Hypnogram / Recipe window
- [ ] Each source can be disabled or deleted
- [ ] Each source can be dragged to reorder
- [ ] The blend mode can be changed for each source
- [ ] A new source can be added at the end and it can either be "New Random" or "New from File (opens file open dialog)"
- [ ] The opacity can be changed for each source
- [ ] You can change the playback speed for each source (if easy)

## Project: Prepare for Beta Release/TestFlight
- [ ] Apple Developer signup, App Store Connect, TestFlight release
- [ ] Collect testers, sort paths, finalize icon

---

## RECENTLY COMPLETED
- Hold `0` in Montage mode to temporarily suspend global effect chain
- Hold `1-9` in Montage mode to solo source and suspend global effects (keeps source effect for preview)
- Add global Source Framing setting (Fill/Fit) persisted in `hypnograph-settings.json` and applied to preview/live/export
- Change the default location of stored Hypnograms to ~/Movies/Hypnograph ?
- I would like the window state to restore including whether clean screen is currently enabled
- When there were no windows in the saved window state then Tab toggles on all windows... may change this to just being a special keystroke for show all windows but not sure yet
- Move Divine into its own product

## Project: Unified Player Architecture
Status: Completed
Shared A/B player infrastructure for Preview and Live with smooth transitions. Foundational work for transitions and volume leveling.
- Docs: `docs/projects/20260116-unified-player-architecture/overview.md`
- Plan: `docs/projects/20260116-unified-player-architecture/implementation-planning.md`

## Project: Hypnogram Transitions
Status: Completed
Visual transitions between clip changes (Preview + Live). Depends on: Unified Player Architecture.
- Docs: `docs/projects/20260116-hypnogram-transitions/overview.md`
- Plan: `docs/projects/20260116-hypnogram-transitions/implementation-planning.md`

- [x] Can do away with lastRecipe, if there is no history or a failure on load we just generate a new hypnogram on start and start a new history
