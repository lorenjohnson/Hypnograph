---
last_reviewed: 2026-01-18T00:00:00Z
---

# Architecture

## Apps and Frameworks

This repo currently contains two macOS apps:

- **Hypnograph** (`HypnographApp`) — the Dream performance app (preview, live display, export).
- **Divine** (`DivineApp`) — a separate app target with its own state and UI.

Both apps share core frameworks (notably `HypnoCore`, plus UI helpers in `HypnoUI`).

## App Structure

### Hypnograph

```
+-------------------------------------------------------------+
| HypnographApp                                               |
| - Owns: HypnographState, Dream                              |
| - Defines: AppCommands                                      |
+-------------------------------------------------------------+
                         |
                         v
+-------------------------------------------------------------+
| ContentView                                                  |
| - Receives current mode (HypnographMode)                    |
| - Builds HUD: globalHUDItems() + mode.hudItems()            |
| - Displays: mode.makeDisplayView()                          |
+-------------------------------------------------------------+
                         |
                         |
                         v
                    +---------+
                    | Dream   |
                    +---------+
```

### Divine

```
+-------------------------------------------------------------+
| DivineApp                                                   |
| - Owns: DivineState, Divine                                 |
| - Defines: DivineAppCommands                                |
+-------------------------------------------------------------+
                         |
                         v
+-------------------------------------------------------------+
| DivineContentView                                           |
| - App-specific UI + commands                                |
+-------------------------------------------------------------+
                         |
                         v
                    +---------+
                    | Divine  |
                    +---------+
```

Hypnograph controls are documented in `docs/reference/controls.md`. Divine has its own command surface.

## Subsystem Docs

These docs are currently a mix of shared (`HypnoCore`) and app-specific (Hypnograph/Divine) details.

- Rendering: `docs/architecture/rendering.md`
- Effects: `docs/architecture/effects.md`
- Media Library: `docs/architecture/media-library.md`
- Dream Players: `docs/architecture/dream-players.md`
- Settings: `docs/architecture/settings.md`
- Recipes: `docs/architecture/recipes.md`

## Module Coordinator Pattern

Each feature module (`Dream`, `LivePlayer`) is a coordinator class that:

```swift
@MainActor
final class Dream: ObservableObject {
    let state: HypnographState

    func makeDisplayView() -> AnyView { ... }   // Main view
    func hudItems() -> [HUDItem] { ... }         // HUD contributions
    @ViewBuilder func compositionMenu() -> some View { ... }  // Menu items
}
```

Modules currently live in `Hypnograph/<Feature>/...` and `Divine/<Feature>/...` (not `Modules/<Name>/`).

## State Hierarchy

```
HypnoCoreConfig (shared core configuration)
    ├── HypnographState (Hypnograph app state)
    │     └── DreamPlayerState (per-player: recipe, playback, effects)
    └── DivineState (Divine app state)
```

- Pass state down via constructor injection
- Forward child `objectWillChange` to parent for SwiftUI reactivity
- Avoid singletons except hardware access (`AudioDeviceManager.shared`)

## Render Pipeline

```
HypnogramRecipe -> RenderEngine -> (internal composition + compositor) -> AVPlayerItem -> AVPlayer
    -> FrameSource (AVPlayerItemVideoOutput) -> PlayerView (MTKView)
```

Detailed render notes live in `docs/architecture/rendering.md`.
Effect-specific details live in `docs/architecture/effects.md`.

## Docs Layout (Planned)

Longer-term, it may be cleaner to split docs by audience and app:

- `docs/` — shared, core docs (primarily `HypnoCore`)
- `Hypnograph/docs/` — Hypnograph-specific docs
- `Divine/docs/` — Divine-specific docs

This re-org will require updating intra-doc links; it can be done as a dedicated docs-only pass.

## Logging Convention

```swift
print("✅ Module: Success")  // Completed
print("⚠️ Module: Warning")  // Non-critical
print("🔴 Module: Error")    // Critical
```

## Error Handling

- Never crash: use `guard` with fallback, not force-unwrap
- Effects return original image on failure (graceful degradation)
- Fallback chain: User config → bundled default → hardcoded
