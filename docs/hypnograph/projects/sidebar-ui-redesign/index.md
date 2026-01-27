# Sidebar UI Redesign

**Status:** In Progress
**Created:** 2026-01-25
**Last Updated:** 2026-01-26

## Overview

Redesign Hypnograph's windowing and UI to use native SwiftUI sidebars with `.ultraThinMaterial` backgrounds. This consolidates several related projects:

- [combine-hud-into-player-settings](../combine-hud-into-player-settings.md) - Merged HUD and player settings
- [app-settings-window](../app-settings-window.md) - App-wide settings decisions
- [command-menu-review](../command-menu-review.md) - Menu structure cleanup

## Design Goals

1. **Two sidebars** - Left for settings, Right for layers/effect chains
2. **Native controls** - Use SwiftUI Slider, Toggle, Picker, Stepper
3. **Material backgrounds** - `.ultraThinMaterial` for glass effect over video
4. **Hideable** - Keyboard shortcuts to toggle sidebars on/off
5. **Clean separation** - Settings (rules for generation) vs. State (current hypnograph)

---

## Final Sidebar Structure

### Sidebar Width Strategy

Sidebars use **fixed widths** (Left: 280pt, Right: 300pt) rather than percentage-based sizing. This follows the pattern of creative apps (Final Cut Pro, Logic Pro, Photos) where:

- The main canvas (video preview) absorbs extra window space
- Sidebar controls have minimum usable widths for sliders, pickers, etc.
- Content doesn't need to scale with window size

*Future consideration*: Resizable sidebars with min/max bounds could be added later if needed.

### Left Sidebar (280pt) - Settings Only

| Section | Controls |
|---------|----------|
| **Watch** | Watch toggle, Play Rate slider, Transition Style picker, Transition Duration slider |
| **Display** | Source Framing picker, Aspect Ratio picker |
| **Audio** | Preview device + volume, Live device + volume |
| **Generation** | Max Layers stepper, Clip Length range slider, Randomize Global Effect toggle + frequency, Randomize Layer Effects toggle + frequency |

### Right Sidebar (300pt)

| Tab               | Purpose                                                                        |
|-------------------|--------------------------------------------------------------------------------|
| **Composition**   | Global settings + Layer stack with selection, blend mode, opacity, effects     |
| **Effect Chains** | Library of saved effect chains with apply-to-Global/Layer context menu         |

---

## Key Design Decisions

### Settings vs. State Separation
- **Settings (left sidebar)** = Rules for generating NEW hypnograms
  - Randomize global effect: on/off + frequency %
  - Randomize layer effects: on/off + frequency %
  - Max layers, clip lengths, transitions, etc.
- **Layers (right sidebar)** = Current hypnograph state
  - What effect chain is applied NOW
  - What layers exist NOW
  - Edit blend mode, opacity, enable/disable

### Layer Selection Model

- Use existing `currentLayer` concept from the app (0 or nil = no layer selected)
- Global is always accessible (no selection concept for Global)
- Selection determines which layer receives "Apply to Selected Layer" from Effect Chains library
- "Apply to Selected Layer" grayed out when `currentLayer === 0` or `nil`
- Visual indicator: accent color tint + border on selected layer row
- Selection persists when switching between Composition and Effect Chains tabs

### Effect Chains in Composition Tab

- **Global section**: Shows current global effect chain name, expandable to edit effects
- **Per-layer**: Each layer can have its own effect chain, expandable when layer is expanded
- **Shared component**: `EffectChainSectionMockup` handles both cases

### Layer Row Display

- **Thumbnail** (56×42) - **NEW FUNCTIONALITY**: Extract frame from video clip for preview
- **Title**: Filename (e.g., "beach_sunset.mp4")
- **Subtitle**: Date + location + blend mode (if not Normal)
- **Solo button** (S) - Yellow when active
- **Visibility button** (eye icon)
- **Expanded state**: Blend mode picker, opacity slider, effect chain section

### Effect Chains Library (Right Tab)

- List of saved effect chains
- Each row shows chain name + effect count badge
- Context menu: Apply to Global, Apply to Selected Layer, Duplicate, Rename, Delete
- Expandable to show/edit individual effects with parameters

---

## Mockup Files

Located in `docs/hypnograph/projects/sidebar-ui-redesign/`:

| File | Description |
|------|-------------|
| `LeftSidebarMockup.swift` | Settings sidebar with sections |
| `RightSidebarMockup.swift` | Layers + Effect Chains tabs with full interaction |
| `FullLayoutMockup.swift` | Both sidebars over video placeholder + bottom HUD |
| `ComponentMockups.swift` | Control style variations for reference |

---

## Phased Implementation Plan

### Phase 1: Foundation & Layout

**Goal**: Get sidebars rendering in the main app with basic structure

**Tasks**:

1. [x] Create `LeftSidebarView.swift` and `RightSidebarView.swift` based on mockups
2. [x] Update `ContentView.swift` to use new sidebars with ZStack overlay pattern
3. [x] Add sidebar visibility state (registered via `WindowState`)
4. [x] Implement keyboard shortcuts: `[`, `]`, `Tab` for sidebar toggling
5. [x] Add Preview/Live mode switcher (segmented control) to top center HUD

**Files to Create**:

- `Hypnograph/Views/LeftSidebarView.swift`
- `Hypnograph/Views/RightSidebarView.swift`
- `Hypnograph/Views/Components/KeyboardHintBar.swift` (bottom HUD)

**Files to Modify**:

- `Hypnograph/Views/ContentView.swift` - Add sidebar overlay

### Phase 2: Settings Migration

**Goal**: Move all PlayerSettingsView functionality to left sidebar

**Tasks**:

1. [x] Wire up existing `Settings` bindings to left sidebar controls
2. [x] Add new settings to `Settings.swift`:
   - `randomGlobalEffect: Bool`
   - `randomGlobalEffectFrequency: Double`
   - `randomLayerEffect: Bool`
   - `randomLayerEffectFrequency: Double`
3. [x] Implement clip length range control (min/max sliders)
4. [x] Connect audio device/volume controls to `Dream.previewAudioDevice`, etc.
5. [x] Migrate Watch Mode toggle
6. [x] Migrate Play Rate slider (with snap points from `PlayRateControl`)

**Files to Modify**:

- `Hypnograph/Settings.swift` - Add randomization settings
- `Hypnograph/Views/LeftSidebarView.swift` - Wire up bindings

**Refactoring Notes**:

- `PlayerSettingsView.PlayRateControl` can be extracted and reused
- `AudioDeviceRow` can be simplified (remove dark mode styling for material background)

### Phase 3: Layers Tab Implementation

**Goal**: Display current hypnograph state with layer selection and effect chains

**Tasks**:

1. [x] Create `LayerRowView` component with:
   - Thumbnail generation (NEW: extract frame from video via AVAssetImageGenerator)
   - Title/subtitle (filename, date, location from PHAsset)
   - Solo/Visibility toggles
   - Selection state visual indicator
2. [x] Implement layer selection state management
3. [x] Wire up Global section:
   - Clip Length display (from `Settings.clipLengthMinSeconds/Max`)
   - Global Effect Chain (from `Dream.activePlayer.globalEffectChain`) *(shown as summary + Edit link to Effects Editor)*
4. [x] Wire up per-layer effect chains (from `HypnogramLayer.effectChain`) *(shown as summary + Edit link to Effects Editor)*
5. [x] Create reusable `EffectChainView` component for displaying/editing chains
6. [x] Implement blend mode and opacity controls per layer

**Data Sources**:

- `Dream.activePlayer.layers: [HypnogramLayer]`
- `HypnogramLayer.effectChain: EffectChain?`
- `Dream.activePlayer.globalEffectChain: EffectChain`

**Files to Create**:

- `Hypnograph/Views/Components/LayerRowView.swift`
- `Hypnograph/Views/Components/EffectChainView.swift`
- `Hypnograph/Views/Components/EffectDefinitionRowView.swift`

**Refactoring Notes**:

- Use existing `currentLayer` for selection state (no new property needed)
- `HypnogramLayer` may need `blendMode` and `opacity` properties if not already present

### Phase 4: Effect Chains Library Tab

**Goal**: Display and manage saved effect chains with apply functionality

**Tasks**:

1. [ ] Create `EffectChainLibraryView` for the right sidebar tab
2. [ ] Load effect chains from `effects.json` library file
3. [ ] Implement "Apply to Global" action
4. [ ] Implement "Apply to Selected Layer" action (requires layer selection state)
5. [ ] Add context menu actions: Duplicate, Rename, Delete
6. [ ] Implement "Save to Library" from Global/Layer context menus

**Files to Create**:

- `Hypnograph/Views/Components/EffectChainLibraryView.swift`
- `Hypnograph/Views/Components/EffectChainLibraryRowView.swift`

**Dependencies**:

- Layer selection state from Phase 3
- Effect chain editing infrastructure from Phase 3

### Phase 5: Deprecation & Cleanup

**Goal**: Remove old UI, update menus, polish

**Tasks**:

1. [ ] Deprecate `HUDView.swift` (functionality moved to Layers tab)
2. [ ] Deprecate `PlayerSettingsView.swift` (functionality moved to left sidebar)
3. [ ] Update `HypnographCommands.swift` to remove obsolete menu items
4. [ ] Review keyboard shortcuts for conflicts
5. [ ] Update any documentation referencing old UI

**Files to Deprecate**:

- `Hypnograph/Views/HUDView.swift`
- `Hypnograph/Views/Components/PlayerSettingsView.swift`

---

## Technical Notes

### Existing Code Alignment

The mockups intentionally stay close to existing functionality. Here's how mockup models map to real code:

| Mockup | Real Code |
|--------|-----------|
| `EffectChainMockup` | `EffectChain` (HypnoCore) |
| `EffectDefinitionMockup` | `EffectDefinition` (HypnoCore) |
| `AnyCodableValueMockup` | `AnyCodableValue` (HypnoCore) |
| `LayerDataMockup` | `HypnogramLayer` (HypnoCore) |

### Settings Already in Place

These settings already exist in `Settings.swift` and just need wiring:

- `watchMode`, `clipLengthMinSeconds`, `clipLengthMaxSeconds`
- `transitionStyle`, `transitionDuration`
- `sourceFraming`, `playerConfig.aspectRatio`, `playerConfig.maxLayers`
- `previewAudioDeviceUID`, `previewVolume`, `liveAudioDeviceUID`, `liveVolume`

### Settings to Add

New settings needed for randomization (in `Settings.swift`):

```swift
var randomGlobalEffect: Bool = true
var randomGlobalEffectFrequency: Double = 0.7  // 70%
var randomLayerEffect: Bool = false
var randomLayerEffectFrequency: Double = 0.3   // 30%
```

### Layer Model Considerations

Current `HypnogramLayer` contains `mediaClip` and `effectChain`. May need to add:

- `blendMode: BlendMode` (if not already present)
- `opacity: Double` (if not already present)
- `isVisible: Bool` (for eye toggle)
- `isSolo: Bool` (for solo toggle)

Or these could be managed in a separate `LayerUIState` wrapper.

### State Management

Consider creating a dedicated `UIState` observable for sidebar-specific state:

```swift
class UIState: ObservableObject {
    @Published var showLeftSidebar = true
    @Published var showRightSidebar = true
    @Published var rightSidebarTab = 0  // 0 = Layers, 1 = Effect Chains
}
```

**Note**: Layer selection uses existing `currentLayer` from the app (not a new property). This ensures selection persists across tab switches and integrates with existing functionality.

---

## Dependencies

- **swiftui-sliders package** (optional) - For production-quality RangeSlider: <https://github.com/spacenation/swiftui-sliders>
- **PHAsset metadata** - For layer subtitle (date, location) - existing infrastructure in media library code
