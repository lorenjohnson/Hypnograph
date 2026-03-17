---
last_reviewed: 2026-03-17
---
# Roadmap

## Current
- [ ] [website-docs-sync-to-files](active/website-docs-sync-to-files.md)
- [ ] [main-architecture-refactor](active/main-architecture-refactor.md)
- [ ] [sidebar-windowization](active/sidebar-windowization.md)
- [ ] [grab-bag-bugs-and-ui-ux-conundrums](active/grab-bag-bugs-and-ui-ux-conundrums.md)
- [ ] Setting global effect preset is a little weird unexpected... Single press clearing of current Effect Chain selection, selecting of another one... Right now feels like adding effects is like adding a chain but actually mutatin ga chain...
- [ ] the "h" hypnograms window. what to do with it...
- [ ] Rendering/saving some Hypnograms results in an error: "🔴 RenderEngine.export failed - RenderError: Export failed: Cannot Decode. Render job failed: The operation couldn't be completed. (Hypnograph.RenderError error 6.)" — happens if any effects load operation were done first
- [ ] Refine packaged Effect Chains Library entries
- [ ] A workflow for adding static file sources. 
- [ ] Finder action "Add to Hypnograph Source" is not installing - Automator action fails. Also, try adding a sourceFolder without any files in it--it may cause  causes a crash?
- [ ] Now layer timeline editor should maybe be turn on/off'able with a button in the Playbar or even its own window?
- [ ] Sets/sequences
- [ ] Review Effect Chains library window to make i maybe more intuitive (recent is a little confusing and probably can/should go below the library/s)
- [ ] [beta-release-testflight](active/beta-release-testflight.md)
- [ ] [direct-download-unsigned-macos-release](active/direct-download-unsigned-macos-release.md)
- [ ] [collaborators-homepage-capture-plan](active/collaborators-homepage-capture-plan.md)

## Backlog
- [composition-timeline-pivot-spike](backlog/composition-timeline-pivot-spike.md)
- [effects-chain-composition-spike](backlog/effects-chain-composition-spike.md)
- [effects-engine-pass-graph-pivot-spike](backlog/effects-engine-pass-graph-pivot-spike.md)
- [sources-window](backlog/sources-window.md)
- clip start / stop potins and duration not just duration (like the range selector for randomize clip speed in behaviour including being able to set an individual frame 
- [add-history-to-hypnograms-favorite-recent-window](backlog/add-history-to-hypnograms-favorite-recent-window.md)
- [in-app-feedback](backlog/in-app-feedback.md)
- [sets-model-direction](backlog/sets-model-direction.md)
- [ ] I'd like to be able to enable/disable effect chain options from the right side bar Effects Cahin tab. Just a round checkbox not a slider.
- [ ] Video playback can freeze/blank while audio continues (AVFoundation stall); current workaround can show black frames — investigate root cause and remove TODO recovery (Can't currently reproduce) [video-playback-stall](active/video-playback-stall.md)
- [export-clip-history-fcpxml](backlog/export-clip-history-fcpxml.md)
- [layer-editor](backlog/layer-editor.md)
- [library-manager](backlog/library-manager.md)
- [location-overlay-effect](backlog/location-overlay-effect.md)
- [preview-frame-buffer-bleed-between-clips](backlog/preview-frame-buffer-bleed-between-clips.md)
- [volume-leveling](backlog/volume-leveling.md)
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
	- [ ] You can change the playback speed for each source (if easy)
- [ ] Explore "Channels" for Hypnograph watching: e.g., select a pin on a map + max radius to constrain random clip selection; or time-based channels with begin/end date (or a slider for time period before/after a date). Or using Apple Foundation to formulate a PHAsset query (e.g. "All photos in and around Berlin, Germany in 2025")
- [ ] Custom Metal blends modes for better destructive shaders/effects. How to integrate our own Metal shaders as Blend Mode options.
- [ ] Midi mapping, Mic input, MIDI Clock, OSC
- [ ] I am questioning whether effect chains should have some sort of preview thumbnails and pressing on the thumbnail applies the effect chain, maybe a small button on the thumbnail takes a snapshot of the current hypnogram to be the new thumbnail for that effect chain?
