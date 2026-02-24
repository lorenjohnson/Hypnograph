# Dream Player State Refactor

## Goal
Separate Dream module into three independent "decks", each with its own recipe and state:
- **Montage Player** - blends all sources together, loops
- **Sequence Player** - plays sources back-to-back
- **Live Display** - external monitor output (Live mode)

## Why
- `HypnographState` became a god object mixing app config, playback state, UI state
- Switching between montage/sequence currently shares the same recipe (confusing)
- Want independent compositions per player that can be copied between decks
- Cleaner architecture for future features

## New Architecture

```
Dream (module)
├── montagePlayer: DreamPlayerState
├── sequencePlayer: DreamPlayerState
├── performanceDisplay: LivePlayer  (moved from HypnographState)
├── activePlayer: DreamPlayerState (computed, based on mode)
└── state: HypnographState (for libraries, settings only)

HypnographState (leaner)
├── settings: Settings (persisted config)
├── library: MediaLibrary
├── currentModuleType: ModuleType
├── activeLibraryKeys, currentLibraryKey
└── (no more recipe, isPaused, effectManager, UI visibility)
```

## DreamPlayerState Properties

```swift
@MainActor
final class DreamPlayerState: ObservableObject {
    // Recipe
    @Published var recipe: HypnogramRecipe

    // Playback
    @Published var currentSourceIndex: Int = 0
    @Published var currentClipTimeOffset: CMTime?
    @Published var isPaused: Bool = false
    @Published var playRate: Float = 0.8
    @Published var effectsChangeCounter: Int = 0

    // Display settings
    @Published var aspectRatio: AspectRatio
    @Published var outputResolution: OutputResolution

    // Generation settings (for New operations)
    @Published var maxSourcesForNew: Int
    @Published var targetDuration: CMTime

    // UI state
    @Published var isHUDVisible: Bool = false
    @Published var isEffectsEditorVisible: Bool = false

    // Effects
    let effectManager = EffectManager()
}
```

## Migration Steps

### 1. Create DreamPlayerState ✅
- New file: `Hypnograph/Modules/Dream/DreamPlayerState.swift`
- Contains all player-specific state
- Has recipe, playback state, effects, UI visibility
- Has navigation methods (nextSource, previousSource, etc.)
- Has resetForNextHypnogram() for cleanup between generations

### 2. Update Dream to own player states ✅
- Added `montagePlayer`, `sequencePlayer` as DreamPlayerState instances
- Added `performanceDisplay` directly on Dream (not from HypnographState)
- Added `activePlayer` computed property based on current mode
- Added `isLiveMode` and `toggleLiveMode()` directly on Dream
- Init creates player states from settings

### 3. Update Dream.swift references ✅
All references updated:
- `state.recipe` → `activePlayer.recipe`
- `state.isPaused` → `activePlayer.isPaused`
- `state.currentSourceIndex` → `activePlayer.currentSourceIndex`
- `state.effectManager` → `activePlayer.effectManager`
- `state.isHUDVisible` → `activePlayer.isHUDVisible`
- `state.isEffectsEditorVisible` → `activePlayer.isEffectsEditorVisible`
- `state.sources` → `activePlayer.sources`
- etc.

Added new methods to Dream:
- `generateNewHypnogram(for:)` - generates random content for a player
- `addSourceToPlayer(_:length:)` - adds source to specific player
- `replaceClipForCurrentSource()` - replaces current clip
- Source management (exclude, delete)

### 4. HypnographState - DEFERRED
Keep all properties for now:
- Views (ContentView, EffectsEditorView) still reference state
- HypnographState is still single source of truth for UI binding
- Will clean up in future iteration when we migrate views to use Dream

### 5. Views - DEFERRED
Views continue to use HypnographState:
- Works because HypnographState still has all properties
- Dream internally uses DreamPlayerState
- Future: migrate views to bind to Dream's player state

### 6. Build and fix compile errors ✅
Build succeeds with new architecture.

### 7. Add Player Settings Modal - TODO
New modal UI for:
- Max Sources for New
- Target Duration
- Play Rate / FPS

## Current State (Dec 2024)
- Dream now owns independent player states
- Each player has its own recipe, effects, playback state
- Switching modes switches which player is active
- HypnographState still has all its properties (for view compatibility)
- Views continue to work without changes

## Next Steps
1. Add Player Settings modal for per-player configuration
2. Migrate views to bind directly to Dream's activePlayer
3. Clean up redundant properties from HypnographState
4. Add "copy recipe to other deck" feature

## Future Features
- Copy recipe from one deck to another
- Per-player watch timer
- Deck-specific effect presets
