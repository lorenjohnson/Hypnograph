# Layer Editor MVP Scope

**Date:** 2025-12-26
**Status:** Draft

## Overview

A layer editor for managing sources in montage mode. Focuses on layer ordering, blend modes, clip timing, and loop visualization. This is explicitly **not** a timeline editor or NLE - it's a layer-centric tool for compositing multiple sources.

### Core Concept

- All layers share the same **total duration** (the montage/recipe target duration)
- Each layer has a **clip** (a slice of a source file) that **loops** to fill that duration
- Users can **trim** clips (adjust start/duration within source file)
- Users can **reorder** layers (z-order)
- Users can set **blend mode** and **audio mute** per layer
- Loop visualization shows where clips repeat

### Model Changes

```swift
// Add to HypnogramSource
var loopEnabled: Bool = true   // Toggle looping on/off
var audioMuted: Bool = false   // Mute audio for this source
```

Existing model already supports:
- `clip.startTime` - where in source file to start
- `clip.duration` - how much of source to play before loop
- `source.blendMode` - blend mode for compositing
- `sources` array order - determines z-order

### UI Layout

```
┌─────────────────────────────────────────────────────────────┐
│ 0s          2s          4s          6s          8s          │  ← Time Ruler
├─────────────────────────────────────────────────────────────┤
│                          ▼                                  │  ← Playhead
├─────────────────────────────────────────────────────────────┤
│ ⋮⋮ 🖼 beach.mov    Screen ▼  🔁 🔊  ━━━━|━━━━|━━━━|━━      │  ← Layer 2 (front)
├─────────────────────────────────────────────────────────────┤
│ ⋮⋮ 🖼 sunset.mp4   Multiply ▼ 🔁 🔇  ━━━━━━━|━━━━━━━|      │  ← Layer 1
├─────────────────────────────────────────────────────────────┤
│ ⋮⋮ 🖼 clouds.mov   Base Layer     🔊  ━━━━━━━━━━━━━━━━━━━━━ │  ← Layer 0 (back)
└─────────────────────────────────────────────────────────────┘

Legend:
  ⋮⋮  = Drag handle for reordering
  🖼  = Thumbnail
  ▼   = Dropdown (blend mode picker)
  🔁  = Loop toggle
  🔊🔇 = Audio mute toggle
  |   = Loop restart marker
  ━   = Clip playing
```

### Clip Bar Interactions

#### Anatomy
```
◀━━━━━━━━━━━━━━━━━▶
↑        ↑        ↑
Left   Body    Right
Handle        Handle
```

#### Drag Actions

| Interaction | Effect |
|-------------|--------|
| Drag left handle | Adjust `startTime` (where in source file to begin) |
| Drag body | Shift `startTime` (slide window through source file) |
| Drag right handle | Adjust `duration` (how much of source before loop) |

Loop markers update live during drag to show new loop positions.

### Behavior

| Interaction | Effect |
|-------------|--------|
| Drag layer row up/down | Reorder z-index (top = front) |
| Drag playhead | Scrub preview to that time |
| Toggle loop 🔁 | Enable/disable looping for layer |
| Loop off + past clip end | Layer disappears abruptly |
| Toggle audio 🔊/🔇 | Mute/unmute audio for layer |
| Blend mode picker | Change blend mode |

---

## Implementation Plan

### Model (Tiny)
- [ ] Add `loopEnabled: Bool` to `HypnogramSource`
- [ ] Add `audioMuted: Bool` to `HypnogramSource`
- [ ] Update Codable conformance

### UI Components

| Component | Effort | Description |
|-----------|--------|-------------|
| LayerEditorView | Small | Main container, vertical ScrollView |
| TimeRuler | Small | Top bar showing 0s → targetDuration |
| Playhead | Small-Medium | Vertical line spanning all rows, draggable |
| LayerRow | Medium | One per source: header + clip bar |
| LayerRowHeader | Small | Drag handle, thumbnail, name, blend picker, toggles |
| ClipBar | Medium | Horizontal bar with loop markers |
| ClipBarHandles | Medium | Left/right drag handles + body drag |

### Behaviors

| Task | Effort |
|------|--------|
| Layer reorder (drag up/down) | Small |
| Blend mode picker | Small |
| Loop toggle | Tiny |
| Audio mute toggle | Tiny |
| Audio mute in CompositionBuilder | Small |
| Preview sync on playhead scrub | Medium |
| Non-looping layer disappear | Small |
| ClipBar drag gestures | Medium |
| Loop marker computation | Small |

### Out of Scope

- Thumbnails on clip bars (solid color for MVP)
- Audio waveforms
- Keyframe animation
- Transitions
- Spatial transforms (scale/position/opacity) - separate Phase 2
- Multiple clips per source

### Open Questions

1. **Where does this UI live?** New panel/sheet? Replace HUD? New mode?
2. **Preview behavior while dragging?** Live updates vs commit-on-release

### Future Phases

#### Phase 2: Spatial Transform
- Add `scale`, `position`, `opacity` to `HypnogramSource`
- Sliders in layer row or inspector panel
- Direct manipulation (drag/pinch) on preview when layer selected
