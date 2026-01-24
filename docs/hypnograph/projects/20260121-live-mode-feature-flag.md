# Live Mode Feature Flag

**Project ID:** 20260121-live-mode-feature-flag
**Status:** Planning
**Created:** 2026-01-21

## Overview

Implement a feature flag system to gate Live Mode functionality, allowing it to be turned off by default and eventually serve as a paid add-on capability.

## Motivation

Live Mode is a specialized feature for live performance workflows (external monitor output, A/B crossfading, live send). Most users don't need this complexity during their core creative work. By feature-flagging it:

1. **Simplify the default experience** - Reduce cognitive load for users who just want to make hypnograms
2. **Progressive disclosure** - Advanced features reveal themselves when needed
3. **Future monetization path** - Live Mode can become a paid add-on
4. **Cleaner codebase** - Explicit boundaries around optional functionality

## Current State

Live Mode is already reasonably well-isolated in the codebase:

| Component | File | Purpose |
|-----------|------|---------|
| LivePlayer | `Hypnograph/Dream/LivePlayer.swift` | Core live playback engine |
| LiveWindow | `Hypnograph/Dream/LiveWindow.swift` | External monitor window management |
| LivePlayerScreen | `Hypnograph/Views/Components/LivePlayerScreen.swift` | Fullscreen live view |
| LivePreviewPanel | `Hypnograph/Views/Components/LivePreviewPanel.swift` | Sidebar preview of live output |
| Commands | `Hypnograph/AppCommands.swift` | Menu items under "Sidebar > Live Display" |

The codebase already uses settings-based conditionals (`watchMode`, window visibility state) that provide a pattern for this work.

## Design Decision

### Approach: Settings Flag with Conditional UI

Add a simple boolean flag to the existing `Settings` struct rather than building a formal feature flag system. This approach:

- Uses existing patterns (minimal new concepts)
- Requires ~50-100 lines of changes across 4-5 files
- Can graduate to a formal system later if needed
- Settings persist in `~/.config/Hypnograph/settings.json`

### What Gets Gated

| Gated (Live-specific) | NOT Gated (Core) |
|-----------------------|------------------|
| Live Preview panel in sidebar | Preview player |
| "Send to Live Display" command | Composition engine |
| External monitor window | Effects system |
| Live/Edit mode toggle | Export functionality |
| Live audio device settings | Preview audio |
| Keyboard shortcuts for Live | All other shortcuts |

The **preview player stays** - that's the core creative loop. Live is specifically about output to external display.

## Implementation Plan

### Phase 1: Add Feature Flag to Settings

**File:** `Hypnograph/Settings.swift`

```swift
// Add to Settings struct
var liveModeEnabled: Bool = false
```

**File:** `Hypnograph/default-settings.json`

```json
{
  "liveModeEnabled": false,
  // ... existing settings
}
```

### Phase 2: Add Convenience Accessor

**File:** `Hypnograph/Dream/Dream.swift`

```swift
// Computed property for easy access
var isLiveModeAvailable: Bool {
    state.settings.liveModeEnabled
}

// Guard the toggle
func toggleLiveMode() {
    guard isLiveModeAvailable else { return }
    liveMode = (liveMode == .edit) ? .live : .edit
}
```

### Phase 3: Gate Menu Commands

**File:** `Hypnograph/AppCommands.swift`

Wrap the "Sidebar > Live Display" menu section:

```swift
// Before
CommandMenu("Sidebar") {
    // ... other items

    Section("Live Display") {
        Toggle("Live Preview", isOn: ...)
        Toggle("Live Mode", isOn: ...)
        Toggle("External Monitor", isOn: ...)
        Button("Send to Live Display") { ... }
        Button("Reset Live Display") { ... }
    }
}

// After
CommandMenu("Sidebar") {
    // ... other items

    if dream.isLiveModeAvailable {
        Section("Live Display") {
            Toggle("Live Preview", isOn: ...)
            Toggle("Live Mode", isOn: ...)
            Toggle("External Monitor", isOn: ...)
            Button("Send to Live Display") { ... }
            Button("Reset Live Display") { ... }
        }
    }
}
```

### Phase 4: Gate Sidebar Panel

**File:** `Hypnograph/Views/ContentView.swift`

Remove Live Preview panel from sidebar when disabled:

```swift
// In the right sidebar stack
if dream.isLiveModeAvailable && state.windowState.isVisible("livePreview") {
    LivePreviewPanel(dream: dream)
}
```

### Phase 5: Gate Keyboard Shortcuts

**File:** `Hypnograph/HypnographAppDelegate.swift`

Guard any global keyboard handlers for Live:

```swift
// For any Live-specific key handling
guard dream?.isLiveModeAvailable == true else { return }
```

### Phase 6: Lazy Initialize LivePlayer (Optional Optimization)

**File:** `Hypnograph/Dream/Dream.swift`

Convert `livePlayer` to lazy initialization:

```swift
// Before
let livePlayer: LivePlayer

// After
private var _livePlayer: LivePlayer?
var livePlayer: LivePlayer {
    if _livePlayer == nil {
        _livePlayer = LivePlayer(...)
    }
    return _livePlayer!
}
```

This saves memory/resources when Live Mode is disabled. Only implement if profiling shows benefit.

### Phase 7: Settings UI

**File:** `Hypnograph/Views/Settings/` (or appropriate location)

Add a toggle in the Settings/Preferences UI:

```swift
Toggle("Enable Live Mode", isOn: $settings.liveModeEnabled)
    .help("Show Live Mode controls for external monitor output and live performance")
```

Consider placing this in an "Advanced" or "Features" section.

## File Change Summary

| File | Change Type | Scope |
|------|-------------|-------|
| `Settings.swift` | Add property | 1 line |
| `default-settings.json` | Add default | 1 line |
| `Dream.swift` | Add accessor + guard toggle | ~10 lines |
| `AppCommands.swift` | Wrap menu section | ~5 lines |
| `ContentView.swift` | Conditional panel | ~3 lines |
| `HypnographAppDelegate.swift` | Guard keyboard handlers | ~5 lines |
| Settings UI (TBD) | Add toggle | ~10 lines |

**Total:** ~35-50 lines of meaningful changes

## Future Considerations

### Graduating to Formal Feature Flags

If more flags are needed, consider a dedicated struct:

```swift
struct FeatureFlags: Codable {
    var liveMode: Bool = false
    var experimentalEffects: Bool = false
    // future flags...
}

// In Settings
var features: FeatureFlags = FeatureFlags()
```

### Paid Add-On Implementation

When Live Mode becomes paid:

1. **Entitlement verification** - Flag becomes verified rather than user-set
2. **License/subscription check** - Validate against a license server or local receipt
3. **Graceful degradation** - Show "upgrade" prompts rather than hiding features entirely
4. **Trial period** - Allow temporary access before requiring purchase

This is out of scope for the current feature flag work but the boolean flag provides the foundation.

### Testing Considerations

- Test app behavior with flag ON and OFF
- Verify no crashes when flag is toggled mid-session
- Ensure settings migration handles missing flag gracefully (Codable defaults)
- Test that keyboard shortcuts don't leak through when disabled

## Open Questions

1. **Default value** - Should `liveModeEnabled` default to `true` or `false`?
   - Recommendation: `false` (simpler default experience)

2. **Settings migration** - How to handle existing users?
   - Codable will use the default value for missing keys
   - Existing users who use Live Mode will need to enable it once

3. **Discoverability** - How do users learn Live Mode exists if it's hidden?
   - Could show a hint in the UI or documentation
   - Settings toggle makes it visible even when disabled

## References

- [Settings.swift](../../Hypnograph/Settings.swift) - Settings schema
- [Dream.swift](../../Hypnograph/Dream/Dream.swift) - Live mode state
- [AppCommands.swift](../../Hypnograph/AppCommands.swift) - Menu commands
- [LivePlayer.swift](../../Hypnograph/Dream/LivePlayer.swift) - Live playback engine
