# Sequences

This line of work is effectively landed. Hypnograph now works from one active multi-composition `Hypnogram`, keeps sequence ordering and `currentCompositionIndex` as document state, separates loop/generate-at-end behavior into runtime transport settings, and exposes sequence authoring through the dock and sequence strip rather than treating history as a separate editing model.

The older `history-as-editing-surface-spike` questions were answered in practice by the sequence work itself. Composition removal, ordering, navigation, and timeline-like authoring now belong to the broader sequence surface rather than to a separate pre-sequences experiment.

What remains worth remembering:

- very long sequences still need better zoom/overview treatment than simple horizontal scrolling
- importing or merging one hypnogram into another is still unresolved
- playhead- and scrub-aware sequence editing is still a follow-on rather than a finished surface

Supersedes:

- `docs/active/sequences.md`
- `docs/active/history-as-editing-surface-spike.md`
