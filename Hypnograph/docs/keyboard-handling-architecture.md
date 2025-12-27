# Keyboard Handling Architecture for Text Fields vs Single-Key Shortcuts

## The Problem (Recurring)

This app uses single-key shortcuts (no modifiers) for quick access:
- Space → pause/play
- S → save snapshot
- E → toggle Effects Editor
- 1-9 → select sources
- etc.

Text fields in modals (Effects Editor, etc.) conflict with these shortcuts. When typing "test", pressing 's' triggers Save Snapshot instead of typing 's'.

**This has regressed multiple times** because the architecture is fragile and spread across multiple files.

## Current Architecture (and Why It Breaks)

### The Approach: FocusedValues + .disabled()

```
┌─────────────────────────────────────────────────────────────────┐
│  Text Field                                                     │
│  └─ @FocusState isTextFieldFocused                              │
│     └─ .focusedValue(\.isTyping, isTextFieldFocused)            │
│                          │                                      │
│                          ▼                                      │
│  AppCommands                                                    │
│  └─ @FocusedValue(\.isTyping) private var isTyping              │
│     └─ .disabled(isTyping == true)                              │
└─────────────────────────────────────────────────────────────────┘
```

### Files Involved

1. **FocusedValues.swift** - Defines `IsTypingKey`
2. **HypnographApp.swift** - `AppCommands` reads `@FocusedValue(\.isTyping)`
3. **EffectsEditorView.swift** - Multiple components expose focus:
   - `ParameterSliderRow` has `@FocusState isTextFieldFocused`
   - `EditableEffectNameHeader` has its own focus state
   - Parent view computes `isTextEditing` from `focusedField` enum
4. **Dream.swift** - `compositionMenu()` and `sourceMenu()` define more shortcuts
5. **Divine.swift** - `compositionMenu()` and `sourceMenu()` define more shortcuts

### Why It Breaks

1. **Multiple .focusedValue() calls override each other**
   - Parent: `.focusedValue(\.isTyping, isTextEditing)`
   - Child: `.focusedValue(\.isTyping, isTextFieldFocused)`
   - SwiftUI uses innermost in responder chain, but behavior is unreliable

2. **Child components have isolated @FocusState**
   - `EditableEffectNameHeader` has its own `@FocusState`
   - Parent's `focusedField` enum doesn't know about it
   - So `isTextEditing` returns false even when editing

3. **Module menus don't check isTyping at all**
   - `Dream.compositionMenu()` shortcuts like "n", "c", "1-9" aren't disabled
   - These steal keystrokes even when text field is focused

4. **FocusedValues are fragile across view hierarchies**
   - Overlays, sheets, and modals may not propagate correctly
   - Depends on exact view tree structure

## Recommended Fix: Centralize with Global State

### Why Global State Is Actually Better Here

The "pure SwiftUI" FocusedValues approach sounds clean but:
- Requires every text field to remember to expose focus
- Requires every shortcut to check focus
- Easy to miss one → regression
- Hard to debug when it breaks

A simple global "isTypingAnywhere" flag is:
- One place to set
- One place to check
- Can't forget
- Easy to debug

### Implementation

**1. Add to HypnographState:**

```swift
// In HypnographState.swift
@Published var isTypingInTextField: Bool = false
```

**2. Create a unified text field wrapper:**

```swift
// TextFieldWrapper.swift
struct HypnoTextField: View {
    let placeholder: String
    @Binding var text: String
    @EnvironmentObject var state: HypnographState
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .focused($isFocused)
            .onChange(of: isFocused) { _, newValue in
                state.isTypingInTextField = newValue
            }
            .onDisappear {
                // Safety: clear if this field was focused
                if isFocused {
                    state.isTypingInTextField = false
                }
            }
    }
}
```

**3. All shortcuts check the flag:**

```swift
// In AppCommands
Button("Save Snapshot") { ... }
    .keyboardShortcut("s", modifiers: [])
    .disabled(state.isTypingInTextField)

// In Dream.compositionMenu()
Button("New Hypnogram") { ... }
    .keyboardShortcut("n", modifiers: [])
    .disabled(state.isTypingInTextField)
```

**4. Replace all TextField/TextEditor usage with HypnoTextField**

### Alternative: NSEvent Global Monitor

If global state feels wrong, use AppKit's event system:

```swift
// In HypnographApp
class KeyboardMonitor: ObservableObject {
    @Published var isFirstResponderTextField: Bool = false

    init() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check if first responder is a text field
            if let firstResponder = NSApp.keyWindow?.firstResponder,
               firstResponder is NSText || firstResponder is NSTextView {
                self?.isFirstResponderTextField = true
                return event // Let it through to text field
            }
            self?.isFirstResponderTextField = false
            return event
        }
    }
}
```

This is more "macOS native" but adds AppKit dependency.

### Best Hybrid Approach

Keep FocusedValues for the mechanism, but:

1. **Single source of truth**: Only ONE `.focusedValue(\.isTyping, ...)` per modal/overlay, at the top level
2. **Child components update parent state**: Pass `Binding<Bool>` or use `@EnvironmentObject`
3. **Audit ALL keyboard shortcuts**: Search for `keyboardShortcut.*modifiers: \[\]` and add `.disabled()`

## Checklist for Adding New Text Fields

- [ ] Use `HypnoTextField` wrapper OR
- [ ] Connect to parent's focus state via binding
- [ ] Verify shortcuts are disabled when focused (test manually)
- [ ] Add to this doc's list of text field locations

## Text Field Locations (Current)

1. `EffectsEditorView.swift`
   - `ParameterSliderRow.compactTextField` - parameter value editing
   - `EditableEffectNameHeader` - effect chain name editing

2. Future locations should use `HypnoTextField` wrapper

## Shortcuts That MUST Check isTyping

Search pattern: `keyboardShortcut.*modifiers: \[\]`

**AppCommands (HypnographApp.swift):**
- ✅ Space (pause)
- ✅ s (save snapshot)
- ✅ ~ (cycle module)
- ✅ w (watch)
- ✅ i (HUD)
- ✅ e (effects editor)
- ✅ p (player settings)
- ✅ l (performance preview)
- ✅ h (hypnogram list)

**Dream.compositionMenu():**
- ❌ ` (toggle mode) - MISSING
- ❌ 1-9 (select source) - MISSING
- ❌ 0 (global layer) - MISSING
- ❌ c (clear effect) - MISSING
- ❌ n (new hypnogram) - MISSING
- ❌ arrow keys (when editor closed) - OK (conditional)

**Dream.sourceMenu():**
- ❌ m (blend mode) - MISSING
- ❌ r (rotate) - MISSING
- ❌ . (random clip) - MISSING
- ❌ delete (delete source) - MISSING

**Divine.compositionMenu():**
- ❌ . (add card) - MISSING
- ❌ arrow keys - MISSING
- ❌ 1-9 (select card) - MISSING
- ❌ delete - MISSING

## Summary

The current FocusedValues approach is architecturally nice but practically fragile. Options:

1. **Quick fix**: Audit all shortcuts, add `.disabled(isTyping == true)` everywhere
2. **Medium fix**: Create `HypnoTextField` wrapper that sets global state
3. **Full fix**: Use NSEvent monitor to detect text field focus at AppKit level

Recommend option 2 for balance of simplicity and robustness.

