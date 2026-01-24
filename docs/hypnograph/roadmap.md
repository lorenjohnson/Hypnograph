---
last_reviewed: 2026-01-07
---

# Roadmap

## KNOWN ISSUES / BUGS

- [ ] Save and Render: Rendering started and another flash message appear at the same time and one of those messages is extraneous 
- [ ] When the Player is not playing / when it is all still images blend modes don't apply and I can't "flash" to a new layer and see it without effects like I can when videos are playing. It should work/work the same in both scenarios. This is also true if I change effects when the player is paused and it is all videos...
- [ ] Updating an Effect Chain title from where it is applied (e.g. global), then saving back to library just seemed to create a new Library Entry instead of saving back to the original library entry.
- [ ] Rendering/saving some Hypnograms results in an error: "🔴 RenderEngine.export failed - RenderError: Export failed: Cannot Decode. Render job failed: The operation couldn't be completed. (Hypnograph.RenderError error 6.)" — happens if any effects load operation were done first
- [ ] Finder action not installing - Automator action fails.

## MINOR PROJECTS

- [ ] Audit and update command menus to make sure the make sense
- [ ] Add settings window and splash screen, branding stuff? "What you are looking for is who is looking." - St. Francis of Assisi
- [ ] Hypnograph: Put what is in HUD view into the top of the Player Settings modal, eliminating the HUD View. Player Settings may get retitled, not sure. But it now takes up more vertical space and goes to top left of screen. We may need to iterate on the styling and what actually stays, as some things in the HUD may just go away or move elsewhere.
- [ ] Window state not saved in Hypnograph. Maybe save it. Also tab when there are no windows shown or to restore, shows a default set of Player Settings and Effects.
- [ ] Consider new default for storage location (e.g. `~/Movies/Hypnograph` instead of `~/Library/Application Support/Hypnograph/recipes`)
- [ ] Confirm the Add Source functionality (which should be mapped to ".") still works.
- [ ] Tweaks to the IFrame Compress effect, because I like it:
  - [ ] Make the period between iframe freezes more jittery by default and maybe add a setitng after trying it out
  - [ ] Same with the other params, more jitter by default but with anticipation of adding a param
  - [ ] When it is done sticking to a mask or whatever you'd call it, it releases seemingly suddenly. Make it more of a fade or erosion.
- [ ] Game Controller mapping revamp back to essentials only

## Projects

- [add-history-to-hypnograms-favorite-recent-window](projects/add-history-to-hypnograms-favorite-recent-window)
- [desktop-fullscreen](projects/desktop-fullscreen.md)
- [export-clip-history-fcpxml](projects/export-clip-history-fcpxml)
- [layer-editor](projects/layer-editor)
- [library-manager](projects/library-manager.md)
- [live-mode-feature-flag](projects/live-mode-feature-flag.md)
- [location-overlay-effect](projects/location-overlay-effect)
- [save-sequences](projects/save-sequences)
- [volume-leveling](projects/volume-leveling)

## IDEAS

### Improve windowing system to be more idiomatic / Swift native while still be unobtrusive

The hidden work here is actually deciding and designing the UI/UX I want first. Which windows exist and what goes in them and what do they look like?

### Integrate a Roadmap feature into both apps

Appears as a command under Hypnograph / Divine left menu and opens a conventional Swift or SwiftUI macOS window.

- [ ] Show a list of upcoming features with a vote option and status of completion

### Prepare for Beta Release/TestFlight

- [ ] Apple Developer signup, App Store Connect, TestFlight release
- [ ] Collect testers, sort paths, finalize icon

### Current Hypnogram / Recipe window

- [ ] Each source can be disabled or deleted
- [ ] Each source can be dragged to reorder
- [ ] The blend mode can be changed for each source
- [ ] A new source can be added at the end and it can either be "New Random" or "New from File (opens file open dialog)"
- [ ] The opacity can be changed for each source
- [ ] You can change the playback speed for each source (if easy)

## RESEARCH & DEVELOPMENT

- [ ] Make Player View a bottom of screen strip instead of a side quarter window. Play with "light up punch buttons" for turning and and off sources and a different color to indicate the currently selected source.
- [ ] Explore how some watch sort of mode where individual sources in a layered montage hypnogram change one by one randomly might work. Start with prototype just to see how the experience feels and if it is worth integrating.
- [ ] Explore "Channels" for Hypnograph watching: e.g., select a pin on a map + max radius to constrain random clip selection; or time-based channels with begin/end date (or a slider for time period before/after a date). Or using Apple Foundation to formulate a PHAsset query (e.g. "All photos in and around Berlin, Germany in 2025")
- [ ] Custom Metal blends modes for better destructive shaders/effects. How to integrate our own Metal shaders as Blend Mode options.
- [ ] Auto blend mode sensing (like based on the relative brightness of the source images). I think I am already doing something like that.
- [ ] Midi mapping, Mic input, MIDI Clock, OSC
- [ ] Bring back randomized effect as an option for randomized hypnogram generation
- [ ] I am questioning whether effect chains should have some sort of preview thumbnails and pressing on the thumbnail applies the effect chain, maybe a small button on the thumbnail takes a snapshot of the current hypnogram to be the new thumbnail for that effect chain?
