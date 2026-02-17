---
last_reviewed: 2026-02-15
---
# Roadmap

## v0.1 Release

- [ ] Blend modes and effects don't visibly apply when player is paused or showing still images (regression — this used to work)
- [ ] Rendering/saving some Hypnograms results in an error: "🔴 RenderEngine.export failed - RenderError: Export failed: Cannot Decode. Render job failed: The operation couldn't be completed. (Hypnograph.RenderError error 6.)" — happens if any effects load operation were done first
- [ ] Finder action "Add to Hypnograph Source" is not installing - Automator action fails. Also, try adding a sourceFolder without any files in it--it may cause  causes a crash?
- [ ] Refine or Remove (feature flag?) the Apple Photos selection window feature
- [ ] Refine packaged Effect Chains Library entries
- [ ] Review Effect Chains library window to make i maybe more intuitive (recent is a little confusing and probably can/should go below the library/s)
- [ ] [record-deck](projects/record-deck.md)
- [ ] [app-settings-window](projects/app-settings-window.md)
- [ ] [command-menu-review](projects/command-menu-review.md)
- [ ] [splash-screen](projects/splash-screen.md)
- [ ] [combine-hud-into-player-settings](projects/combine-hud-into-player-settings.md)
- [ ] [save-fullscreen-state](projects/save-fullscreen-state.md)
- [ ] [live-mode-feature-flag](projects/live-mode-feature-flag.md)
- [ ] [in-app-feedback](projects/in-app-feedback.md)
- [ ] [volume-leveling](projects/volume-leveling)
- [ ] [beta-release-testflight](projects/beta-release-testflight.md)

## Backlog
- clip start / stop potins and duration not just duration (like the range selector for randomize clip speed in behaviour including being able to set an individual frame 
- [ ] I'd like to be able to enable/disable effect chain options from the right side bar Effects Cahin tab. Just a round checkbox not a slider.
- [ ] Video playback can freeze/blank while audio continues (AVFoundation stall); current workaround can show black frames — investigate root cause and remove TODO recovery (Can't currently reproduce) [video-playback-stall](projects/video-playback-stall.md)
- [export-clip-history-fcpxml](projects/export-clip-history-fcpxml)
- [add-history-to-hypnograms-favorite-recent-window](projects/add-history-to-hypnograms-favorite-recent-window)
- [layer-editor](projects/layer-editor)
- [library-manager](projects/library-manager.md)
- [location-overlay-effect](projects/location-overlay-effect)
- [ ] Tweaks to the IFrame Compress effect, because I like it:
  -  Make the period between iframe freezes more jittery by default and maybe add a setitng after trying it out
  -  Same with the other params, more jitter by default but with anticipation of adding a param
  - When it is done sticking to a mask or whatever you'd call it, it releases seemingly suddenly. Make it more of a fade or erosion.
- [ ]  In-App Roadmap Display: Show the roadmap in-app, let users vote on feature priorities. Related to but separate from in-app feedback. Would need to decide on data source (local markdown, remote JSON) and how votes aggregate. #idea

# Research & Development

- [ ] Investigate replacing custom settings/state persistence with UserDefaults or @AppStorage. Goal: reduce owned code, be more idiomatic. What would we lose? What could we delete?
- [ ] "Randomize Effect" as a toggle for randomized hypnogram generation
- [ ] Randomization option for an entire effects chain?
- [ ] Auto blend mode sensing (like based on the relative brightness of the source images). I think I am already doing something like that.
- [ ]  Current Hypnogram / Recipe window
	- [ ] Each source can be disabled or deleted
	- [ ] Each source can be dragged to reorder
	- [ ] The blend mode can be changed for each source
	- [ ] A new source can be added at the end and it can either be "New Random" or "New from File (opens file open dialog)"
	- [ ] The opacity can be changed for each source
	- [ ] You can change the playback speed for each source (if easy)
- [ ] Make Player View a bottom of screen strip instead of a side quarter window. Play with "light up punch buttons" for turning and and off sources and a different color to indicate the currently selected source.
- [ ] Explore how some watch sort of mode where individual sources in a layered montage hypnogram change one by one randomly might work. Start with prototype just to see how the experience feels and if it is worth integrating.
- [ ] Explore "Channels" for Hypnograph watching: e.g., select a pin on a map + max radius to constrain random clip selection; or time-based channels with begin/end date (or a slider for time period before/after a date). Or using Apple Foundation to formulate a PHAsset query (e.g. "All photos in and around Berlin, Germany in 2025")
- [ ] Custom Metal blends modes for better destructive shaders/effects. How to integrate our own Metal shaders as Blend Mode options.
- [ ] Midi mapping, Mic input, MIDI Clock, OSC
- [ ] I am questioning whether effect chains should have some sort of preview thumbnails and pressing on the thumbnail applies the effect chain, maybe a small button on the thumbnail takes a snapshot of the current hypnogram to be the new thumbnail for that effect chain?
