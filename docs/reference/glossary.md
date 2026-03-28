---
last_reviewed: 2026-03-28
---

# Glossary

This is a working glossary for Hypnograph's core model. It is intentionally high level and product-facing. The goal is to make the main UI and saved-file structure easier to talk about clearly, while still being useful to developers who need to relate that model back to the code.

One important note: the current codebase does not yet line up cleanly with this glossary. In particular, the type currently named `HypnographSession` behaves most like what this glossary calls a Hypnogram, and the type currently named `Hypnogram` behaves most like what this glossary calls a Composition.

**Hypnogram**  
The top-level saved unit. A Hypnogram is the file or document you save, reopen, and organize. A Hypnogram contains one or more Compositions in sequence, along with file-level metadata such as a snapshot thumbnail and creation date.

**Composition**  
One playable item inside a Hypnogram. A Composition is what plays as a unit before the app advances to another Composition. A Composition contains one or more Layers, along with composition-level settings such as duration, play rate, and global Effects.

**Layer**  
One visual layer inside a Composition. A Layer points to the underlying media source being used, includes the relevant playback window for that media such as the selected time range for video or display length for still images, and carries layer-level settings such as transforms, blend mode, opacity, mute state, and any per-Layer Effect Chain.

**Source**  
The video or image that serves as the basis for a Layer in a Composition. A Source can come from a specific file selected on disk, from Apple Photos, or, in the more common Hypnograph flow, from a randomly selected file or Apple Photos asset drawn from the configured pool of available Sources in the Sources window.

**Effect Chain**  
A reusable ordered set of Effects that run one after another. Each Effect processes the frame and passes its output forward to the next Effect in the chain. An Effect Chain can be applied globally to a Composition or locally to an individual Layer.

**Effect**  
A single visual effect inside an Effect Chain. In the current implementation, Effects are fundamentally Metal shader-based and may expose parameters that can be adjusted in the UI. For people who want to go deeper, Effects can be created and modified in Effects Composer.

**Effect Chains Library**  
The reusable library of saved Effect Chains available inside Hypnograph Studio. It is used to store, browse, load, and reapply Effect Chains across different Compositions and Layers.
