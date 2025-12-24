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

### FocusedValues (SwiftUI-native approach)

The solution uses SwiftUI's `FocusedValues` mechanism to expose text field focus state to Commands without polluting global app state:

**1. Define FocusedValueKey** (`Hypnograph/FocusedValues.swift`):
```swift
struct IsTypingKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var isTyping: Bool? {
        get { self[IsTypingKey.self] }
        set { self[IsTypingKey.self] = newValue }
    }
}
```

**2. Views expose focus via `.focusedValue()`**:
```swift
// ParameterSliderRow (has local @FocusState isTextFieldFocused)
.focusedValue(\.isTyping, isTextFieldFocused)

// EditableEffectNameHeader
.focusedValue(\.isTyping, isTextFieldFocused)

// EffectsEditorView (for its own isTextEditing computed property)
.focusedValue(\.isTyping, isTextEditing)
```

**3. AppCommands reads via `@FocusedValue`**:
```swift
struct AppCommands: Commands {
    @FocusedValue(\.isTyping) private var isTyping

    var body: some Commands {
        Button("Save Snapshot") { ... }
            .keyboardShortcut("s", modifiers: [])
            .disabled(isTyping == true)
    }
}
```

### Data Flow

1. User clicks text field in EffectsEditorView
2. SwiftUI sets local @FocusState to true
3. View's `.focusedValue(\.isTyping, true)` exposes state to responder chain
4. AppCommands receives updated `@FocusedValue(\.isTyping)`
5. User presses 's' key
6. Menu command is disabled (isTyping == true), key event passes to text field
7. When user clicks away, focus state becomes false, shortcuts re-enable

### Why `.disabled()` Instead of Guards

- `.disabled()` **does work** in SwiftUI Commands (contrary to some assumptions)
- Disabled commands don't fire at all, avoiding keystroke consumption ambiguity
- Menu items visually reflect availability (grayed out when typing)
- Cleaner code without repeated guard boilerplate
- Direct bindings like `$state.isHUDVisible` can be used instead of custom Binding wrappers

### Advantages of FocusedValues

1. **No global state** - Focus is transient UI state that stays in the view hierarchy
2. **Automatic cleanup** - SwiftUI manages the responder chain automatically
3. **Multi-window/modal safe** - Each window/modal can expose its own focus state independently
4. **No callbacks** - Views simply expose state, Commands simply read it

### Files Changed

1. `Hypnograph/FocusedValues.swift` - New file defining IsTypingKey
2. `Hypnograph/HypnographApp.swift` - Uses `@FocusedValue(\.isTyping)` and `.disabled(isTyping == true)`
3. `Hypnograph/Views/EffectsEditorView.swift` - Added `.focusedValue()` to text field components

