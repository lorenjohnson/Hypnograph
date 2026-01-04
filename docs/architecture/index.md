---
last_reviewed: 2026-01-03T21:17:01Z
---

# Architecture

## App Structure

```
+-------------------------------------------------------------+
| HypnographApp                                                |
| - Owns: HypnographState, Dream, Divine                      |
| - Defines: AppCommands                                       |
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
                 +-------+-------+
                 |               |
                 v               v
            +---------+     +---------+
            | Dream   |     | Divine  |
            +---------+     +---------+
```

Controls (commands, HUD, controller) are documented in `docs/reference/controls.md`.

## Subsystem Docs

- Rendering: `docs/architecture/rendering.md`
- Effects: `docs/architecture/effects.md`
- Media Library: `docs/architecture/media-library.md`
- Dream Players: `docs/architecture/dream-players.md`
- Settings: `docs/architecture/settings.md`
- Recipes: `docs/architecture/recipes.md`

## Module Coordinator Pattern

Each feature module (`Dream`, `Divine`, `PerformanceDisplay`) is a coordinator class that:

```swift
@MainActor
final class Dream: ObservableObject {
    let state: HypnographState

    func makeDisplayView() -> AnyView { ... }   // Main view
    func hudItems() -> [HUDItem] { ... }         // HUD contributions
    @ViewBuilder func compositionMenu() -> some View { ... }  // Menu items
}
```

Modules live in `Modules/<Name>/` with coordinator + views + player state.

## State Hierarchy

```
HypnographState (app-wide: settings, library, current module)
    └── DreamPlayerState (per-player: recipe, playback, effects)
```

- Pass state down via constructor injection
- Forward child `objectWillChange` to parent for SwiftUI reactivity
- Avoid singletons except hardware access (`AudioDeviceManager.shared`)

## Render Pipeline

```
HypnogramRecipe -> RenderEngine -> (internal composition + compositor) -> AVPlayer
```

Detailed render notes live in `docs/architecture/rendering.md`.
Effect-specific details live in `docs/architecture/effects.md`.

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
