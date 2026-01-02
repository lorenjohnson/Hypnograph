# Architecture

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
HypnogramRecipe → CompositionBuilder → FrameCompositor → RenderEngine → AVPlayer
```

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

