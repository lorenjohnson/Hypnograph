---
last_reviewed: 2026-01-07
---

# Roadmap

## Recently Completed

- Hold `0` in Montage mode to temporarily suspend global effect chain
- Hold `1-9` in Montage mode to solo source and suspend global effects (keeps source effect for preview)
- Change the default location of stored Hypnograms to ~/Movies/Hypnograph ?
- I would like the window state to restore including whether clean screen is currently enabled
- When there were no windows in the saved window state then Tab toggles on all windows... may change this to just being a special keystroke for show all windows but not sure yet
- Move Divine into its own product

## Research & Development
- [ ] Custom Metal blends modes for better destructive shaders/effects. How to integrate our own Metal shaders as Blend Mode options.
- [ ] Auto blend mode sensing (like based on the relative brightiness of the source images). I think I am already doing something like that.
- [ ] Midi mapping, Mic input, MIDI Clock, OSC
- [ ] Bring back randomized effect as an option for randomized hypnogram generation
- [ ] Live Mode is a bit confusing in this product
- [ ] I want there to be a history of Hypnograms regardless of whether or not they were saved so we can always go back when one looked good. The history should be maybe 100 or so back or ? maybe configurable in settings.json with a default setting of 10
- [ ] I am questioning whether effects chains ("Treatments")should be named or if they maybe are just a thumbnail and pressing on the Treatment thumbnail applies the treatment or maybe a small button on the thumbnail takes a snapshot of the current hypnogram to be the new thumbnail for that treatment.

## Known Issues / Bugs
- [ ] Rendering/saving some Hypnograms results in an error: "🔴 RenderEngine.export failed - RenderError: Export failed: Cannot Decode. Render job failed: The operation couldn’t be completed. (Hypnograph.RenderError error 6.)"
- [ ] Window state not saved in Hypnograph
- [ ] Increase XcodeBuild MCP timeout to >60s (UI tests time out).
- [ ] **Effect name editing broken** - Opens edit mode but can't type. `isTyping` focus disconnect once any effects load operation were done first
- [ ] **Sequence mode saving** - Fails silently or incorrectly.
- [ ] **Output height/width ignored** - Settings file values not applied.
- [ ] **Finder action not installing** - Automator action fails.
- [ ] First load of app seemed to not connect to apple photos but relauches were fine, in both apps

## Minor Projects:
- [ ] Watch mode to be more watchable...
  - [ ] Blend between subsequent Hypnograms like by overlapping sources... R&D but so curious.
  - [ ] Looping: Make it optional such that when it is off and you're in watch mode a new Hypnogram is generated when the previous one ends, unless the clip was shorter than a predetermined minimum length (2s?) in which case it will either be skipped or looped. The play length of a recipe is the length of the  longest running clip in the sources (up to the max duration of course). I guess this should be a player setting in the Watch toggle area.
  - [ ] Flash of image before processed in Player should be avoided/eliminated. A transition to black before the next image is shown would be better. A fade out and fade in would extra nice with a new Player Setting for "Transition Style" (none, fade, punk)
  - [ ] Volume leveling (optional)
- [ ] Bring back Favorites store for saving favorites (by file path or Apple Photos ID?. Pressing F when viewing an Apple Photos asset it should be added to the FavoritesStore as well as to the HypnogramFavorites album in Apple Photos. This keystroke only works when in Sequence mode on any curently playing asset or when in Montage mone on a particular source (not global). Otherwse it gives a short flash message notice "Select a source to favorite" (we should add a basic style for notice vs warning flash messages and this is a warning). Maybe just use an emoji for the warnings and the rest stay the same. In Divine mode this also works for the active card and adds to DivineFavorites in Apple Photos if it is a Photos asset.
- [ ] The DeleteStore functionality should also put the photo or video in the HypnogramDeletions album in Apple Photos if it is an ApplePhotos aset.
- [ ] Add "Player Settings" style control panel for Divine with settings: Allow Reversed toggle, Max Card (int)
- [ ] Add a "+ New Hypnogram" button on the player view
- [ ] Make Player View a bottom of screen strip instead of a side quarter window. Play with "light up punch buttons" for turning and and off sources and a different color to indicate the currently selected source.
- [ ] Tweaks to the IFrame Compress effect, because I like it:
  - [ ] Make the period between iframe freezes more jittery by default and maybe add a setitng after trying it out
  - [ ] Same with the other params, more jitter by default but with anticipation of adding a param
  - [ ] When it is done sticking to a mask or whatever you'd call it, it releases seemingly suddenly. Make it more of a fade or erosion.
- [ ] Divine: Save layouts somehow (Snapshots are a good start), but saving a recipe for restore would be a better first step probably
- [ ] Hypnograph: Combine more of what is in HUD into Player Settings modal
- [ ] Consider new default for storage location (e.g. `~/Movies/Hypnograph` instead of `~/Library/Application Support/Hypnograph/recipes`)
- [ ] Game Controller mapping revamp back to essentials only

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
