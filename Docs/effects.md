# Effects System

Effects are pure functions: `(context, image) → image`.

## Creating a New Effect

```swift
final class MyEffect: Effect {
    var name: String { "My Effect" }
    var requiredLookback: Int { 0 }  // 0=stateless, 30+=temporal

    static var parameterSpecs: [String: ParameterSpec] {
        ["intensity": .float(default: 0.5, range: 0...1)]
    }

    init?(params: [String: AnyCodableValue]?) {
        let p = Params(params, specs: Self.parameterSpecs)
        self.intensity = p.float("intensity")
    }

    func apply(to image: CIImage, context: inout RenderContext) -> CIImage { ... }
    func reset() { /* clear temporal state */ }
    func copy() -> Effect { MyEffect(params: nil)! }
}
```

**Key principles:**
- `parameterSpecs` is source of truth - JSON only specifies non-defaults
- Use `Params` helper for extraction with spec defaults
- Register in `EffectRegistry.swift` with kebab-case type name
- `copy()` isolates export from preview state

## Temporal Effects

Use `final class` with `requiredLookback` (30-120 for datamosh-style). Override `reset()` to clear history.

## Metal Effects

Files: `MyMetalEffect.swift` + `MyShader.metal` with `myKernel` function.

**Always bounds-check:** `if (gid.x >= output.get_width()) return;`

## Export Isolation

```swift
let exportRecipe = recipe.copyForExport()
let exportManager = EffectManager.forExport(recipe: exportRecipe)
```

