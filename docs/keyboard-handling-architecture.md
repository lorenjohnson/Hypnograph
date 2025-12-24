# Keyboard Handling Architecture for Effects Editor Text Field Focus

## Problem

In a macOS SwiftUI app, the Effects Editor overlay contains text input fields (parameter values, effect names). When users clicked into these text fields, keyboard input wasn't working properly because global keyboard shortcuts defined in the app's Commands struct were capturing keystrokes before they could reach the text fields.

Affected shortcuts (all with no modifiers):
- Space → toggles pause/play
- S → save snapshot
- W → toggle watch mode
- I → toggle HUD
- E → toggle Effects Editor
- P → toggle Performance Preview
- ~ → cycle module

## Architecture

### State Management

The app uses a central `HypnographState` class (ObservableObject, @MainActor) that holds all shared app state. A property tracks text field focus:

```swift
/// Whether a text field is currently focused (blocks single-key shortcuts)
@Published var isTextFieldFocused: Bool = false
```

### Text Field Components

Two view components contain text fields that need to signal focus state:

1. **ParameterSliderRow** - For numeric/string parameter editing
   - Has its own `@FocusState private var isTextFieldFocused: Bool`
   - Added callback: `var onTextFieldFocusChange: ((Bool) -> Void)?`
   - Observes focus changes and calls callback:
   ```swift
   .onChange(of: isTextFieldFocused) { _, focused in
       onTextFieldFocusChange?(focused)
   }
   ```

2. **EditableEffectNameHeader** - For editing effect names
   - Same pattern: local @FocusState, callback, onChange observer

### Call Sites

Where these components are instantiated, the callback is wired to the state:

```swift
ParameterSliderRow(
    name: key,
    value: value,
    effectType: def.resolvedType,
    spec: specs[key],
    onChange: { newValue in ... },
    onTextFieldFocusChange: { focused in
        state.isTextFieldFocused = focused
    }
)
```

### Keyboard Shortcuts

In `HypnographApp.swift`, the `AppCommands` struct defines menu commands with keyboard shortcuts. Each unmodified shortcut uses `.disabled()` to prevent firing when text fields are focused:

**For Button commands:**
```swift
Button(state.isPaused ? "Play" : "Pause") {
    state.togglePause()
}
.keyboardShortcut(.space, modifiers: [])
.disabled(state.isTextFieldFocused)
```

**For Toggle commands:**
```swift
Toggle("Info HUD", isOn: $state.isHUDVisible)
    .keyboardShortcut("i", modifiers: [])
    .disabled(state.isTextFieldFocused)
```

### Data Flow

1. User clicks text field in EffectsEditorView
2. SwiftUI sets local @FocusState to true
3. .onChange fires, calls onTextFieldFocusChange(true)
4. Callback sets state.isTextFieldFocused = true
5. User presses 's' key
6. Menu command is disabled, so key event passes through to text field
7. When user clicks away, same flow sets isTextFieldFocused = false

### Why `.disabled()` Instead of Guards

- `.disabled()` **does work** in SwiftUI Commands (contrary to some assumptions)
- Disabled commands don't fire at all, avoiding keystroke consumption ambiguity
- Menu items visually reflect availability (grayed out when typing)
- Cleaner code without repeated guard boilerplate
- Direct bindings like `$state.isHUDVisible` can be used instead of custom Binding wrappers

### Files Changed

1. `Hypnograph/HypnographState.swift` - Added isTextFieldFocused property
2. `Hypnograph/HypnographApp.swift` - Added `.disabled(state.isTextFieldFocused)` to all unmodified shortcut handlers
3. `Hypnograph/Views/EffectsEditorView.swift` - Added callback to ParameterSliderRow and EditableEffectNameHeader, wired at call sites

### Known Limitations

1. Focus is modeled as global mutable app state (a boolean), which can become stale
2. Only EffectsEditorView text fields set this flag - other text fields elsewhere may have the same issue
3. If text field loses focus unexpectedly, the flag may not update

### Future Improvement: FocusedValues

A more SwiftUI-native approach would use:
1. A shared `@FocusState` enum as single source of truth
2. `FocusedValues` to expose typing state to Commands without polluting global state
3. This scales better for multi-window and avoids callback wiring

