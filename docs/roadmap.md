---
last_reviewed: 2026-01-04T22:36:32Z
---

# Roadmap

- Change the default locaiton of stored Hypnograms to ~/Movies/Hypnograph ?
- I would like the window state to restore including whether clean screen is currently enabled
- When there were no windows in the saved window state then Tab toggles on all windows... may change this to just being a special keystroke for show all windows but not sure yet

- Move Divine into its own product, and focus it on ios usage possibly? It just looks at a single Apple Photos directory or file directory for simplicity

- I want there to be a history of Hypnograms regardless of whether or not they were saved so we can always go back when one looked good. The history should be maybe 100 or so back or ? maybe configurable in settings.json with a default setting of 10

- I am questioning whether effects chains ("Treatments")should be named or if they maybe are just a thumbnail and pressing on the Treatment thumbnail applies the treatment or maybe a small button on the thumbnail takes a snapshot of the current hypnogram to be the new thumbnail for that treatment.

## Research & Development
- [ ] Custom Metal blends modes for better destructive shaders/effects
- [ ] Auto blend mode sensing (like based on the relative brightiness of the source images)
- [ ] Midi mapping, Mic input, MIDI Clock, OSC

## Known Issues / Bugs
- [ ] Rendering/saving some Hypnograms results in an error
  - [ ] "🔴 HypnogramRenderer: Export failed - RenderError: Export failed: Cannot Decode. Render job failed: The operation couldn’t be completed. (Hypnograph.RenderError error 6.)"
- [ ] Increase XcodeBuild MCP timeout to >60s (UI tests time out).
- [ ] **Effect name editing broken** - Opens edit mode but can't type. `isTyping` focus disconnect.
- [ ] **Sequence mode saving** - Fails silently or incorrectly.
- [ ] **Output height/width ignored** - Settings file values not applied.
- [ ] **Finder action not installing** - Automator action fails.

## Minor Projects:
- [ ] Put Render Video and Save on a hot keye and retitle the menu item to "Save and Rednder" (Opt-Cmd-S?)
- [ ] Combine most of what is in HUD into Player Settings modal
- [ ] Consider new default for storage location (e.g. `~/Movies/Hypnograph` instead of `~/Library/Application Support/Hypnograph/recipes`)
- [ ] Game Controller mapping revamp back to essentials only
- [ ] Rename PerformanceDisplay module to align with LivePlayer (e.g. LiveDisplay)

## Project: Make Divine its own product
- [ ] Make the core components needed by Divine mode modular and re-usable and get the app compiling with those as depednencies before moving Divine mode into its own product which will also require these dependencies.

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
