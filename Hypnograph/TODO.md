maxSources → maxSources
activeSourceCount → activeSourceCount
layers → layers
layersForRender → sourcesForRender
sourceBlendIndices → sourceBlendIndices
sourceTransforms → sourceTransforms (if present)
currentLayerIndex → currentSourceIndex (Montage already uses this)
nextSource → nextSource
prevSource → prevSource
selectSource → selectSource
goBackOneSource → goBackOneSource
primeRandomSources → primeRandomSources
nextCandidateForCurrentSource → nextCandidateForCurrentSource
acceptCandidateForCurrentSource → acceptCandidateForCurrentSource
cycleBlendModeForCurrentSource → cycleBlendModeForCurrentSource



- Not paying attention to outputHeight, Width from settings file
- 
- Video should not switch when actively working on it. Double check autoPrime setting snd timer, and maybe turn off by default in my settings but make sure there is a hotkey for enabling it

- Ability to rotate, reposition and re-size a video! (how is this stored?)
  I would love to have the following feature in both Montage and Sequence:

  Adjust mode = Toggles on when user hit the "a" key
  in Adjust mode the arrow keys operate to move the current source around on the canvas, CMD upArrow / downArrow serve to Zoom in/out and Cmd-rightArrow / leftArrow rotate the image.
- Video exclude list
  - X to add to exclude list
  - Add function to CLI tool for this for finder integration
  - Can I have the App add a Finder action 
- Video favorites list

- Review saving recipe / source bundle for Hypnogram
- Use same videos in both Montage and Sequence mode, so that switching between them doesn't change the source

- Why is exclude source and such not in common between modes? Same with source prep like rotations and such...

---

Refactor so Hypnogram curent sources selections are stored in Session above Mode in a/the state object?

Right now each mode owns its own “current source” data, so there isn’t a single object that can both identify the current clip and replace it:

Montage’s current source comes from HypnogramState (candidate/selected arrays).
Sequence keeps its own sequenceClips inside SequenceMode, not in HypnogramState.
The exclusion backing store and loader are already global (see ExclusionStore and VideoSourcesLibrary.applyExclusions()), so once a path is added, all future random picks avoid it across modes. The bit that’s still mode-specific is “what is the current source?” and “how do I replace it?” because the data lives in different places.

If you want a single call, we’d need to refactor Sequence so the state owns its clips (or inject a shared “current source” accessor/mutator that each mode can supply). Until then, the cleanest is still currentMode.excludeCurrentSource() as we have now, with Montage calling into state and Sequence updating its own list.

I can refactor Sequence to push its clips/transforms into HypnogramState so both modes share the same API, but that’s a larger change. Let me know if you want me to take that on now.