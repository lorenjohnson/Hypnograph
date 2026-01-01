# Patches from Augment Session (Mode Switcher + Autosave Removal)

These patches capture the changes made in the Augment session on 2024-12-31.

## Cleanly Patchable (apply with `git apply`)

### 01-player-settings-mode-switcher.patch
**File:** `PlayerSettingsView.swift`
**What it does:** Adds a row of three mode buttons (Montage/Sequence/Perf) to the Player Settings panel header. Buttons are full-width and highlight when active.

### 02-performance-preview-header.patch  
**File:** `PerformancePreviewView.swift`
**What it does:** Renames header from "Performance" to "Preview" and updates comment.

### 03-dream-cycle-mode.patch
**File:** `Dream.swift`
**What it does:** Adds `cycleMode()` function that cycles Montage → Sequence → Performance → Montage. Updates the backtick menu item to use it. **NOTE:** Line numbers marked XXX - you'll need to find the `// MARK: - Mode` section and apply manually, OR apply after the refactor is complete.

---

## NOT Patchable (intertwined with refactor)

These changes were made but depend on the refactor's `EffectsSession` architecture:

### effectsAutosave removal
- `Settings.swift` - Removed `effectsAutosave` property
- `HypnographApp.swift` - Removed autosave quit prompt and `isAutosaveEnabled` callback
- `DreamPlayerState.swift` - Removed `effectsSession.isAutosaveEnabled = true` line
- `PerformanceDisplay.swift` - Removed `effectsSession.isAutosaveEnabled = true` line

**Reason:** The refactor replaced `EffectConfigLoader` with `EffectsSession`. The autosave removal was done in the context of the new architecture.

### Merge checkbox in Open Effects Library
- `EffectChainLibraryActions.swift` - Added merge checkbox, `merge:` parameter to load functions
- `EffectsSession.swift` - Added `merge(chains:)` method

**Reason:** These changes use the `EffectsSession` API introduced by the refactor.

### Restore Default Effects Library button
- `EffectsEditorView.swift` - Replaced autosave toggle with "Restore Default Effects Library" button

**Reason:** Uses `EffectChainLibraryActions.restoreDefaultLibrary(session:)` which requires the refactor.

---

## Recommended Approach

1. Apply patches 01 and 02 cleanly
2. For patch 03, manually add `cycleMode()` after `toggleMode()` in Dream.swift and update the menu
3. The autosave/merge changes should come with the refactor since they depend on it

