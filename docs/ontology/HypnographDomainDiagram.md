# Hypnograph Domain Diagram (Curated)

This is a curated, naming-oriented view of the core domain entities (media → recipe → render).

For the full, generated graph of *all* discovered Swift types and relationships, see:

- `docs/ontology/hypnograph-ontology.mmd` (filtered)
- `docs/ontology/hypnograph-ontology-full.mmd` (full)
- `docs/ontology/types.json` (machine-readable)

```mermaid
graph TD
  %% Media models (origin of bytes)
  MediaSource["HypnoCore.MediaSource<br/>(url | external)"]
  MediaFile["HypnoCore.MediaFile<br/>(selectable asset)"]
  VideoClip["HypnoCore.VideoClip<br/>(media slice of MediaFile)"]

  %% Recipe models (what to render)
  HypnogramSource["HypnoCore.HypnogramSource<br/>(LAYER: media slice + transforms + blend + effects)"]
  HypnogramClip["HypnoCore.HypnogramClip<br/>(CLIP (sequence item): layers + global effects + duration)"]
  HypnogramRecipe["HypnoCore.HypnogramRecipe<br/>(SEQUENCE/RECIPE: ordered clips + snapshot)"]
  EffectChain["HypnoCore.EffectChain"]

  %% Renderer pipeline (how it renders)
  SourceLoader["HypnoCore.SourceLoader"]
  LoadedSource["HypnoCore.LoadedSource<br/>(AVAsset/CIImage + metadata)"]
  CompositionBuilder["HypnoCore.CompositionBuilder"]
  RenderEngine["HypnoCore.RenderEngine"]

  %% App state (who owns recipes)
  Dream["Hypnograph.Dream"]

  MediaSource -->|backs| MediaFile
  MediaFile -->|sliced by| VideoClip

  VideoClip -->|is the clip of| HypnogramSource
  HypnogramSource -->|per-layer| EffectChain
  HypnogramClip -->|contains many| HypnogramSource
  HypnogramClip -->|global| EffectChain
  HypnogramRecipe -->|contains many| HypnogramClip

  HypnogramSource -->|loaded by| SourceLoader
  SourceLoader -->|produces| LoadedSource
  HypnogramClip -->|built by| CompositionBuilder
  CompositionBuilder -->|uses| SourceLoader
  RenderEngine -->|drives| CompositionBuilder

  Dream -->|owns| HypnogramRecipe
```

## Ideal vocabulary overlay (proposed)

This keeps the *structure* identical to current code, but swaps in the “more memorable” nouns:

- **HypnographSession** = sequence/container of playable items
- **Hypnogram** = one playable item (1..N layers)
- **HypnogramLayer** = one layer inside a hypnogram
- **MediaClip** = a time slice of a selected media asset

```mermaid
graph TD
  %% Media models (proposed nouns)
  MediaOrigin["MediaOrigin<br/>(= MediaSource)"]
  MediaAsset["MediaAsset<br/>(= MediaFile)"]
  MediaClip["MediaClip<br/>(= VideoClip)"]

  %% Composition models (proposed nouns)
  HypnogramLayer["HypnogramLayer<br/>(= HypnogramSource)"]
  Hypnogram["Hypnogram<br/>(= HypnogramClip)"]
  HypnographSession["HypnographSession<br/>(= HypnogramRecipe)"]

  MediaOrigin --> MediaAsset
  MediaAsset --> MediaClip

  MediaClip --> HypnogramLayer
  Hypnogram -->|contains many| HypnogramLayer
  HypnographSession -->|contains many| Hypnogram
```
